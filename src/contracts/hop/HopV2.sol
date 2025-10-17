pragma solidity ^0.8.0;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import { IExecutor } from "src/contracts/hop/interfaces/IExecutor.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IOFT2 } from "src/contracts/hop/interfaces/IOFT2.sol";
import { HopMessage } from "src/contracts/hop/interfaces/IHopV2.sol";
import { IHopComposer } from "src/contracts/hop/interfaces/IHopComposer.sol";


abstract contract HopV2 is Ownable2StepUpgradeable {

    struct HopV2Storage {
        uint32 localEid;
        address endpoint;
        bool paused;
        mapping(address oft => bool isApproved) approvedOft;
        mapping(bytes32 message => bool isProcessed) messageProcessed;
        mapping(uint32 eid => bytes32 hop) remoteHop;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.HopV2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant HopV2StorageLocation = 
        0x6f2b5e4a4e4e1ee6e84aeabd150e6bcb39c4b05494d47809c3cd3d998f859100;

    function _getHopV2Storage() private pure returns (HopV2Storage storage $) {
        assembly {
            $.slot := HopV2StorageLocation
        }
    }

    event SendOFT(address oft, address indexed sender, uint32 indexed dstEid, bytes32 indexed to, uint256 amount);
    event MessageHash(address oft, uint32 indexed srcEid, uint64 indexed nonce, bytes32 indexed composeFrom);

    error InvalidOFT();
    error HopPaused();
    error NotEndpoint();
    error InsufficientFee();
    error RefundFailed();

    constructor() {
        _disableInitializers();
    }

    function __init_HopV2(
        uint32 _localEid,
        address _endpoint,
        address[] memory _approvedOfts
    ) internal {
        __Ownable2Step_init();

        HopV2Storage storage $ = _getHopV2Storage();
        $.localEid = _localEid;
        $.endpoint = _endpoint;
        for (uint256 i=0; i<_approvedOfts.length; i++) {
            $.approvedOft[_approvedOfts[i]] = true;
        }
    }

    // Public methods
    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable {
        sendOFT(_oft, _dstEid, _recipient, _amountLD, 0, "");
    }    

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD, uint128 _dstGas, bytes memory _data) public virtual payable {
        HopV2Storage storage $ = _getHopV2Storage();
        if ($.paused) revert HopPaused();
        if (!$.approvedOft[_oft]) revert InvalidOFT();

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: $.localEid,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient
        });

        // Transfer the OFT token to the hop
        _amountLD = removeDust(_oft, _amountLD);
        if (_amountLD > 0) SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);

        uint256 sendFee;
        if (_dstEid == $.localEid) {
            // Sending from fraxtal => fraxtal- no LZ send needed
            _sendLocal({
                _oft: _oft,
                _amount: _amountLD,
                _isTrustedHopMessage: true,
                _hopMessage: hopMessage,
                _data: _data
            });
        } else {
            sendFee = _sendToDestination({
                _oft: _oft,
                _amountLD: _amountLD,
                _isTrustedHopMessage: true,
                _hopMessage: hopMessage,
                _data: _data
            });
        }

        // Validate the msg.value
        _handleMsgValue(sendFee);

        emit SendOFT(_oft, msg.sender, _dstEid, _recipient, _amountLD);
    }
    
    // Helper functions
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
            recipient: _recipient
        });

        SendParam memory sendParam = _generateSendParam({
            _amountLD: removeDust(_oft, _amount),
            _hopMessage: hopMessage,
            _data: _data
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        return fee.nativeFee + quoteHop(_dstEid, _dstGas, _data);
    }

    function removeDust(address oft, uint256 _amountLD) public view returns (uint256) {
        uint256 decimalConversionRate = IOFT2(oft).decimalConversionRate();
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }

    // internal methods
    function _sendLocal(
        address _oft,
        uint256 _amount,
        bool _isTrustedHopMessage,
        HopMessage memory _hopMessage,
        bytes memory _data
    ) internal {
        // transfer the OFT token to the recipient
        address recipient = address(uint160(uint256(_hopMessage.recipient)));
        if (_amount > 0) SafeERC20.safeTransfer(IERC20(IOFT(_oft).token()), recipient, _amount);

        // call the compose if there is data
        if (_data.length != 0) {
            IHopComposer(recipient).hopCompose({
                _isTrustedHopMessage: _isTrustedHopMessage,
                _srcEid: _hopMessage.srcEid,
                _sender: _hopMessage.sender,
                _oft: _oft,
                _amount: _amount,
                _data: _data
            });
        }
    }

    function _sendToDestination(
        address _oft,
        uint256 _amountLD,
        bool _isTrustedHopMessage,
        HopMessage memory _hopMessage,
        bytes memory _data
    ) internal returns (uint256) {
        // generate sendParam
        SendParam memory sendParam = _generateSendParam({
            _amountLD: removeDust(_oft, _amountLD),
            _hopMessage: _hopMessage,
            _data: _data
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

        if (_amountLD > 0) SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, _amountLD);
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));

        return fee.nativeFee + quoteHop(_hopMessage.dstEid, _hopMessage.dstGas, _data);
    }

    function _validateComposeMessage(address _oft, bytes calldata _message) internal returns (bool isTrustedHopMessage, bool isDuplicateMessage) {
        HopV2Storage storage $ = _getHopV2Storage();
        
        if (msg.sender != $.endpoint) revert NotEndpoint();
        if ($.paused) revert HopPaused();
        if (!$.approvedOft[_oft]) revert InvalidOFT();

        // Decode message
        uint32 srcEid = OFTComposeMsgCodec.srcEid(_message);
        bytes32 composeFrom = OFTComposeMsgCodec.composeFrom(_message);
        uint64 nonce = OFTComposeMsgCodec.nonce(_message);

        bytes32 messageHash = keccak256(abi.encode(_oft, srcEid, nonce, composeFrom));
        isTrustedHopMessage = $.remoteHop[srcEid] == composeFrom;

        if ($.messageProcessed[messageHash]) {
            return (isTrustedHopMessage, true);
        } else {
            $.messageProcessed[messageHash] = true;
            emit MessageHash(_oft, srcEid, nonce, composeFrom);
            return (isTrustedHopMessage, false);
        }
    }

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
    function pause(bool _paused) external onlyOwner {
        HopV2Storage storage $ = _getHopV2Storage();
        $.paused = _paused;
    }

    function setApprovedOft(address _oft, bool _isApproved) external onlyOwner {
        HopV2Storage storage $ = _getHopV2Storage();
        $.approvedOft[_oft] = _isApproved;
    }

    function setRemoteHop(uint32 _eid, address _remoteHop) external {
        setRemoteHop(_eid, bytes32(uint256(uint160(_remoteHop))));
    }

    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) public onlyOwner {
        _setRemoteHop(_eid, _remoteHop);
    }

    function _setRemoteHop(uint32 _eid, bytes32 _remoteHop) internal {
        HopV2Storage storage $ = _getHopV2Storage();
        $.remoteHop[_eid] = _remoteHop;
    }

    function recoverERC20(address tokenAddress, address recipient, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(recipient, tokenAmount);
    }

    function setMessageProcessed(address _oft, uint32 _srcEid, uint64 _nonce, bytes32 _composeFrom) external onlyOwner {
        HopV2Storage storage $ = _getHopV2Storage();
        
        bytes32 messageHash = keccak256(abi.encode(_oft, _srcEid, _nonce, _composeFrom));
        $.messageProcessed[messageHash] = true;
        emit MessageHash(_oft, _srcEid, _nonce, _composeFrom);
    }    

    function recoverETH(address recipient, uint256 tokenAmount) external onlyOwner {
        payable(recipient).call{ value: tokenAmount }("");
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

    // virtual functions to be overridden
    function quoteHop(uint32 _dstEid, uint128 _dstGas, bytes memory _data) public view virtual returns (uint256) {}
    function _generateSendParam(uint256 _amountLD, HopMessage memory _hopMessage, bytes memory _data) internal view virtual returns (SendParam memory) {}
}