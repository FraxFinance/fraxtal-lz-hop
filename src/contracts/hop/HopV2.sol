pragma solidity ^0.8.0;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import { IExecutor } from "src/contracts/hop/interfaces/IExecutor.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IOFT2 } from "src/contracts/hop/interfaces/IOFT2.sol";
import { IHopV2, HopMessage } from "src/contracts/hop/interfaces/IHopV2.sol";
import { IHopComposer } from "src/contracts/hop/interfaces/IHopComposer.sol";

abstract contract HopV2 is AccessControlEnumerableUpgradeable, IHopV2, IHopComposer {
    uint32 internal constant FRAXTAL_EID = 30255;

    // keccak256("REMOTE_ADMIN_ROLE")
    bytes32 public constant REMOTE_ADMIN_ROLE = 0x7504870cf250183030f060283f976f9f7212253a7a239db522c96ff3fe750c0b;

    struct HopV2Storage {
        /// @dev EID of this chain
        uint32 localEid;
        /// @dev LZ endpoint on this chain
        address endpoint;
        /// @dev Admin-controlled boolean to pause hops
        bool paused;
        /// @dev Mapping to validate only trusted OFTs
        mapping(address oft => bool isApproved) approvedOft;
        /// @dev Mapping to track messages to prevent replays / duplicate messages
        mapping(bytes32 message => bool isProcessed) messageProcessed;
        /// @dev Mapping to track the Hop on a remote chain
        mapping(uint32 eid => bytes32 hop) remoteHop;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.HopV2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant HopV2StorageLocation = 0x6f2b5e4a4e4e1ee6e84aeabd150e6bcb39c4b05494d47809c3cd3d998f859100;

    function _getHopV2Storage() private pure returns (HopV2Storage storage $) {
        assembly {
            $.slot := HopV2StorageLocation
        }
    }

    event SendOFT(address oft, address indexed sender, uint32 indexed dstEid, bytes32 indexed to, uint256 amount);
    event MessageHash(address oft, uint32 indexed srcEid, uint64 indexed nonce, bytes32 indexed composeFrom);

    error InvalidOFT();
    error InvalidSourceEid();
    error HopPaused();
    error NotEndpoint();
    error NotHop();
    error NotAuthorized();
    error InsufficientFee();
    error RefundFailed();
    error FailedRemoteSetCall();

    modifier onlyAuthorized() {
        if (!(hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(REMOTE_ADMIN_ROLE, msg.sender))) {
            revert NotAuthorized();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function __init_HopV2(uint32 _localEid, address _endpoint, address[] memory _approvedOfts) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        HopV2Storage storage $ = _getHopV2Storage();
        $.localEid = _localEid;
        $.endpoint = _endpoint;
        for (uint256 i = 0; i < _approvedOfts.length; i++) {
            $.approvedOft[_approvedOfts[i]] = true;
        }
    }

    // Public methods

    /// @notice Send an OFT to a destination without encoded data
    /// @param _oft Address of OFT
    /// @param _dstEid Destination EID
    /// @param _recipient bytes32 representation of recipient
    /// @param _amountLD Amount of OFT to send
    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable {
        sendOFT(_oft, _dstEid, _recipient, _amountLD, 0, "");
    }

    /// @notice Send an OFT to a destination with encoded data
    /// @dev Check the FraxtalHopV2.remoteHop(_dstEid) to ensure the destination chain is supported.  If the destination
    ///      is not supported, tokens/messages would be stuck on Fraxtal and require a team intervention to recover.
    /// @param _oft Address of OFT
    /// @param _dstEid Destination EID
    /// @param _recipient bytes32 representation of recipient
    /// @param _amountLD Amount of OFT to send
    /// @param _data Encoded data to pass
    function sendOFT(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) public payable virtual {
        HopV2Storage storage $ = _getHopV2Storage();
        if ($.paused) revert HopPaused();
        if (!$.approvedOft[_oft]) revert InvalidOFT();

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: $.localEid,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        // Transfer the OFT token to the hop. Clean off dust for the sender that would otherwise be lost through LZ.
        _amountLD = removeDust(_oft, _amountLD);
        if (_amountLD > 0) SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);

        uint256 sendFee;
        if (_dstEid == $.localEid) {
            // Sending from src => src - no LZ send needed (sendFee remains 0)
            _sendLocal({ _oft: _oft, _amount: _amountLD, _hopMessage: hopMessage });
        } else {
            sendFee = _sendToDestination({
                _oft: _oft,
                _amountLD: _amountLD,
                _isTrustedHopMessage: true,
                _hopMessage: hopMessage
            });
        }

        // Validate the msg.value
        _handleMsgValue(sendFee);

        emit SendOFT(_oft, msg.sender, _dstEid, _recipient, _amountLD);
    }

    // Callback to set admin functions from the Fraxtal msig
    function hopCompose(
        uint32 _srcEid,
        bytes32 _sender,
        address _oft,
        uint256 /* _amount */,
        bytes memory _data
    ) external override {
        HopV2Storage storage $ = _getHopV2Storage();
        // Only allow composes from trusted OFT
        if (!$.approvedOft[_oft]) revert InvalidOFT();

        // Only allow composes originating from fraxtal
        if (_srcEid != FRAXTAL_EID) revert InvalidSourceEid();

        // Only allow self-calls (via lzCompose())
        if (msg.sender != address(this)) revert NotHop();

        // Only allow composes where the sender is approved
        _checkRole(DEFAULT_ADMIN_ROLE, address(uint160(uint256(_sender))));

        (bool success, ) = address(this).call(_data);
        if (!success) revert FailedRemoteSetCall();
    }

    // Helper functions

    /// @notice Get the gas cost estimate of going from this chain to a destination chain
    /// @param _oft Address of OFT to send
    /// @param _dstEid Destination EID
    /// @param _recipient Address of recipient upon destination
    /// @param _amount Amount to transfer (dust will be removed)
    /// @param _dstGas Amount of gas to forward to the destination
    /// @param _data Encoded data to pass to the destination
    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amount,
        uint128 _dstGas,
        bytes memory _data
    ) public view returns (uint256) {
        uint32 localEid_ = localEid();
        if (_dstEid == localEid_) return 0;

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: localEid_,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        SendParam memory sendParam = _generateSendParam({
            _amountLD: removeDust(_oft, _amount),
            _hopMessage: hopMessage
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        return fee.nativeFee + quoteHop(_dstEid, _dstGas, _data);
    }

    /// @notice Remove the dust amount of OFT so that the message passed is the message received
    function removeDust(address oft, uint256 _amountLD) public view returns (uint256) {
        uint256 decimalConversionRate = IOFT2(oft).decimalConversionRate();
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }

    // internal methods

    /// @dev Send the OFT and execute hopCompose on this chain (locally)
    function _sendLocal(address _oft, uint256 _amount, HopMessage memory _hopMessage) internal {
        // transfer the OFT to the recipient
        address recipient = address(uint160(uint256(_hopMessage.recipient)));
        if (_amount > 0) SafeERC20.safeTransfer(IERC20(IOFT(_oft).token()), recipient, _amount);

        // call the compose if there is data
        if (_hopMessage.data.length != 0) {
            IHopComposer(recipient).hopCompose({
                _srcEid: _hopMessage.srcEid,
                _sender: _hopMessage.sender,
                _oft: _oft,
                _amount: _amount,
                _data: _hopMessage.data
            });
        }
    }

    /// @dev Send the OFT to execute hopCompose on a destination chain
    function _sendToDestination(
        address _oft,
        uint256 _amountLD,
        bool _isTrustedHopMessage,
        HopMessage memory _hopMessage
    ) internal returns (uint256) {
        // generate sendParam
        SendParam memory sendParam = _generateSendParam({
            _amountLD: removeDust(_oft, _amountLD),
            _hopMessage: _hopMessage
        });

        MessagingFee memory fee;
        if (_isTrustedHopMessage) {
            // Executes in:
            // - sendOFT()
            // - Fraxtal lzCompose() when remote hop is sender
            fee = IOFT(_oft).quoteSend(sendParam, false);
        } else {
            // Executes when:
            // - Fraxtal lzCompose() from unregistered sender
            fee.nativeFee = msg.value;
        }

        // Send the OFT to the recipient
        if (_amountLD > 0) SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, _amountLD);
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));

        // Return the total amount charged in the send.  On fraxtal, this is only the native fee as there is no hop needed.
        return fee.nativeFee + quoteHop(_hopMessage.dstEid, _hopMessage.dstGas, _hopMessage.data);
    }

    /// @dev Check the incoming message integrity
    function _validateComposeMessage(
        address _oft,
        bytes calldata _message
    ) internal returns (bool isTrustedHopMessage, bool isDuplicateMessage) {
        HopV2Storage storage $ = _getHopV2Storage();

        if (msg.sender != $.endpoint) revert NotEndpoint();
        if ($.paused) revert HopPaused();
        if (!$.approvedOft[_oft]) revert InvalidOFT();

        // Decode message
        uint32 srcEid = OFTComposeMsgCodec.srcEid(_message);
        bytes32 composeFrom = OFTComposeMsgCodec.composeFrom(_message);
        uint64 nonce = OFTComposeMsgCodec.nonce(_message);

        // Encode the unique message data to prevent replays
        bytes32 messageHash = keccak256(abi.encode(_oft, srcEid, nonce, composeFrom));

        // True if the composer is a registered RemoteHop, otherwise false
        isTrustedHopMessage = $.remoteHop[srcEid] == composeFrom;

        if ($.messageProcessed[messageHash]) {
            // The message is a duplicate, we end execution early
            return (isTrustedHopMessage, true);
        } else {
            // We process the message and continue execution
            $.messageProcessed[messageHash] = true;
            emit MessageHash(_oft, srcEid, nonce, composeFrom);
            return (isTrustedHopMessage, false);
        }
    }

    /// @dev Check the msg value of the tx
    function _handleMsgValue(uint256 _sendFee) internal {
        if (msg.value < _sendFee) {
            revert InsufficientFee();
        } else if (msg.value > _sendFee) {
            // refund redundant fee to sender
            (bool success, ) = payable(msg.sender).call{ value: msg.value - _sendFee }("");
            if (!success) revert RefundFailed();
        }
    }

    // Admin functions
    function pause(bool _paused) public onlyAuthorized {
        HopV2Storage storage $ = _getHopV2Storage();
        $.paused = _paused;
    }

    function setApprovedOft(address _oft, bool _isApproved) public onlyAuthorized {
        HopV2Storage storage $ = _getHopV2Storage();
        $.approvedOft[_oft] = _isApproved;
    }

    function setRemoteHop(uint32 _eid, address _remoteHop) public {
        setRemoteHop(_eid, bytes32(uint256(uint160(_remoteHop))));
    }

    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) public onlyAuthorized {
        _setRemoteHop(_eid, _remoteHop);
    }

    function _setRemoteHop(uint32 _eid, bytes32 _remoteHop) internal {
        HopV2Storage storage $ = _getHopV2Storage();
        $.remoteHop[_eid] = _remoteHop;
    }

    function recoverERC20(
        address tokenAddress,
        address recipient,
        uint256 tokenAmount
    ) public onlyAuthorized {
        IERC20(tokenAddress).transfer(recipient, tokenAmount);
    }

    function setMessageProcessed(
        address _oft,
        uint32 _srcEid,
        uint64 _nonce,
        bytes32 _composeFrom
    ) public onlyAuthorized {
        HopV2Storage storage $ = _getHopV2Storage();

        bytes32 messageHash = keccak256(abi.encode(_oft, _srcEid, _nonce, _composeFrom));
        $.messageProcessed[messageHash] = true;
        emit MessageHash(_oft, _srcEid, _nonce, _composeFrom);
    }

    function recoverETH(address recipient, uint256 tokenAmount) public onlyAuthorized {
        (bool success, ) = payable(recipient).call{ value: tokenAmount }("");
        require(success);
    }

    // Storage views
    function localEid() public view returns (uint32) {
        HopV2Storage storage $ = _getHopV2Storage();
        return $.localEid;
    }

    function endpoint() external view returns (address) {
        HopV2Storage storage $ = _getHopV2Storage();
        return $.endpoint;
    }

    function paused() external view returns (bool) {
        HopV2Storage storage $ = _getHopV2Storage();
        return $.paused;
    }

    function approvedOft(address oft) external view returns (bool isApproved) {
        HopV2Storage storage $ = _getHopV2Storage();
        return $.approvedOft[oft];
    }

    function messageProcessed(bytes32 message) external view returns (bool isProcessed) {
        HopV2Storage storage $ = _getHopV2Storage();
        return $.messageProcessed[message];
    }

    function remoteHop(uint32 eid) public view returns (bytes32 hop) {
        HopV2Storage storage $ = _getHopV2Storage();
        return $.remoteHop[eid];
    }

    // virtual functions to override

    /// @notice Quote the hop of a send. Returns 0 when originating from fraxtal as the destination only receives and does not hop further.
    function quoteHop(uint32 _dstEid, uint128 _dstGas, bytes memory _data) public view virtual returns (uint256) {}
    function _generateSendParam(
        uint256 _amountLD,
        HopMessage memory _hopMessage
    ) internal view virtual returns (SendParam memory) {}
}
