// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IOFT2 } from "./interfaces/IOFT2.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ILayerZeroDVN } from "./interfaces/ILayerZeroDVN.sol";
import { ILayerZeroTreasury } from "./interfaces/ILayerZeroTreasury.sol";
import { IExecutor } from "./interfaces/IExecutor.sol";
import { IHopComposer } from "./interfaces/IHopComposer.sol";
import { IHopV2 } from "./interfaces/IHopV2.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== RemoteHopV2 ============================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract RemoteHopV2 is Ownable2Step, IOAppComposer, IHopV2 {
    uint32 constant FRAXTAL_EID = 30255;
    bool public paused = false;
    bytes32 public fraxtalHop;
    uint256 public numDVNs = 2;
    uint256 public hopFee = 1; // 10000 based so 1 = 0.01%
    mapping(uint32 => bytes) public executorOptions;
    mapping(address => bool) public approvedOft;
    mapping(bytes32 => bool) public messageProcessed;

    address public immutable ENDPOINT;
    address public immutable EXECUTOR;
    address public immutable DVN;
    address public immutable TREASURY;
    uint32 public immutable EID;

    event SendOFT(address oft, address indexed sender, uint32 indexed dstEid, bytes32 indexed to, uint256 amountLD);
    event Hop(address oft, address indexed recipient, uint256 amount);
    event MessageHash(address oft, uint64 indexed nonce, bytes32 indexed fraxtalHop);

    error InvalidOFT();
    error HopPaused();
    error NotEndpoint();
    error InsufficientFee();
    error RefundFailed();
    error ZeroAmountSend();
    error InvalidSourceChain();
    error InvalidSourceHop();

    constructor(
        bytes32 _fraxtalHop,
        uint256 _numDVNs,
        address _ENDPOINT,
        address _EXECUTOR,
        address _DVN,
        address _TREASURY,
        uint32 _EID,
        address[] memory _approvedOfts
    ) Ownable(msg.sender) {
        fraxtalHop = _fraxtalHop;
        numDVNs = _numDVNs;
        ENDPOINT = _ENDPOINT;
        EID = _EID;
        EXECUTOR = _EXECUTOR;
        DVN = _DVN;
        TREASURY = _TREASURY;

        for (uint256 i = 0; i < _approvedOfts.length; i++) {
            approvedOft[_approvedOfts[i]] = true;
        }
    }

    // Admin functions
    function recoverERC20(address tokenAddress, address recipient, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(recipient, tokenAmount);
    }

    function recoverETH(address recipient, uint256 tokenAmount) external onlyOwner {
        payable(recipient).call{ value: tokenAmount }("");
    }

    function setFraxtalHop(address _fraxtalHop) external {
        setFraxtalHop(bytes32(uint256(uint160(_fraxtalHop))));
    }

    function setFraxtalHop(bytes32 _fraxtalHop) public onlyOwner {
        fraxtalHop = _fraxtalHop;
    }

    function setNumDVNs(uint256 _numDVNs) external onlyOwner {
        numDVNs = _numDVNs;
    }

    function setHopFee(uint256 _hopFee) external onlyOwner {
        hopFee = _hopFee;
    }

    function setExecutorOptions(uint32 eid, bytes memory _options) external onlyOwner {
        executorOptions[eid] = _options;
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function toggleOFTApproval(address _oft, bool _approved) external onlyOwner {
        approvedOft[_oft] = _approved;
    }

    // receive ETH
    receive() external payable {}

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD) external payable {
        sendOFT(_oft, _dstEid, _to, _amountLD, 0, "");
    }

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD, uint128 _composeGas, bytes memory _composeMsg) public payable {
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();
        _amountLD = removeDust(_oft, _amountLD);
        SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);
        if (_dstEid == EID) {
            SafeERC20.safeTransfer(IERC20(IOFT(_oft).token()), address(uint160(uint256(_to))), _amountLD);
            if (_composeMsg.length != 0) {
                IHopComposer(address(uint160(uint256(_to)))).hopCompose(EID, bytes32(uint256(uint160(msg.sender))), _oft, _amountLD, _composeMsg);
            }
            if (msg.value > 0) {
                (bool success, ) = address(msg.sender).call{ value: msg.value }("");
                if (!success) revert RefundFailed();
            }
        } else {
            _sendViaFraxtal(_oft, _dstEid, _to, _amountLD, _composeGas, _composeMsg);
        }
        emit SendOFT(_oft, msg.sender, _dstEid, _to, _amountLD);
    }

    function _sendViaFraxtal(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD, uint128 _composeGas, bytes memory _composeMsg) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _amountLD,
            _composeGas: _composeGas,
            _composeMsg: _composeMsg
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        uint256 finalFee = fee.nativeFee + quoteHop(_dstEid, _composeGas, _composeMsg);
        if (finalFee > msg.value) revert InsufficientFee();

        // Send the oft
        SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, _amountLD);
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));

        // Refund the excess
        if (msg.value > finalFee) {
            (bool success, ) = address(msg.sender).call{ value: msg.value - finalFee }("");
            if (!success) revert RefundFailed();
        }
    }

    function _generateSendParam(
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint128 _composeGas,
        bytes memory _composeMsg
    ) internal view returns (SendParam memory sendParam) {
        sendParam.dstEid = FRAXTAL_EID;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        if (_dstEid == FRAXTAL_EID && _composeMsg.length == 0) { 
            // Send directly to Fraxtal, no compose needed
            sendParam.to = _to;
        } else {
            bytes memory options = OptionsBuilder.newOptions();
            if (_composeGas < 400000) _composeGas = 400000;
            sendParam.to = fraxtalHop; 
            uint128 fraxtalGas = 1000000;
            if (_composeGas > fraxtalGas && _dstEid == FRAXTAL_EID) fraxtalGas = _composeGas;
            options = OptionsBuilder.addExecutorLzComposeOption(options, 0, fraxtalGas, 0);
            sendParam.extraOptions = options;
            if (_composeMsg.length == 0) sendParam.composeMsg = abi.encode(_to, _dstEid, _composeGas, "");
            else sendParam.composeMsg = abi.encode(_to, _dstEid, _composeGas, abi.encode(EID, msg.sender, _composeMsg));
        }
    }

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint128 _composeGas,
        bytes memory _composeMsg
    ) public view returns (uint256) {
        if (_dstEid == EID) return 0;
        _amountLD = removeDust(_oft, _amountLD);
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _amountLD,
            _composeGas: _composeGas,
            _composeMsg: _composeMsg
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        fee.nativeFee += quoteHop(_dstEid, _composeGas, _composeMsg);
        return fee.nativeFee;
    }

    function quoteHop(uint32 _dstEid, uint128 _composeGas, bytes memory _composeMsg) public view returns (uint256 finalFee) {
        uint256 dvnFee = ILayerZeroDVN(DVN).getFee(_dstEid, 5, address(this), "");
        bytes memory options = executorOptions[_dstEid];
        if (options.length == 0) options = hex"01001101000000000000000000000000000493E0";
        if (_composeMsg.length != 0) {
            if (_composeGas < 400000) _composeGas = 400000;
            options = abi.encodePacked(options,hex"010013030000", _composeGas);
        }
        uint256 executorFee = IExecutor(EXECUTOR).getFee(_dstEid, address(this), 36, options);
        uint256 totalFee = dvnFee * numDVNs + executorFee;
        uint256 treasuryFee = ILayerZeroTreasury(TREASURY).getFee(address(this), _dstEid, totalFee, false);
        finalFee = totalFee + treasuryFee;
        finalFee = (finalFee * (10000 + hopFee)) / 10000;
    }

    function removeDust(address oft, uint256 _amountLD) internal view returns (uint256) {
        uint256 decimalConversionRate = IOFT2(oft).decimalConversionRate();
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a token swap.
    ///      This method expects the encoded compose message to contain the swap amount and recipient address.
    /// @dev source: https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
    /// @param _oft The address of the originating OApp/Token.
    /// @param /*_guid*/ The globally unique identifier of the message
    /// @param _message The encoded message content in the format of the OFTComposeMsgCodec.
    /// @param /*Executor*/ Executor address
    /// @param /*Executor Data*/ Additional data for checking for a specific executor
    function lzCompose(
        address _oft,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*Executor*/,
        bytes calldata /*Executor Data*/
    ) external payable override {
        if (msg.sender != ENDPOINT) revert NotEndpoint();
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();
        if (OFTComposeMsgCodec.srcEid(_message)!= FRAXTAL_EID) revert InvalidSourceChain();
        if (OFTComposeMsgCodec.composeFrom(_message) != fraxtalHop) revert InvalidSourceHop();
        {
            uint64 nonce = OFTComposeMsgCodec.nonce(_message);
            bytes32 messageHash = keccak256(abi.encode(_oft, nonce, fraxtalHop));
            // Avoid duplicated messages
            if (!messageProcessed[messageHash]) {
                messageProcessed[messageHash] = true;
            } else {
                return;
            }
            emit MessageHash(_oft, nonce, fraxtalHop);
        }

        // Extract the composed message from the delivered message using the MsgCodec
        (bytes32 _recipient, bytes memory _composeMsg) = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (bytes32, bytes));
        uint256 _amount = OFTComposeMsgCodec.amountLD(_message);
        address _recipientAddress = address(uint160(uint256(_recipient)));
        address __oft = _oft;
        if (_amount > 0) SafeERC20.safeTransfer(IERC20(IOFT(_oft).token()), _recipientAddress, _amount);
        if (_composeMsg.length != 0) {
            (uint32 srcEid, bytes32 srcAddress, bytes memory _composeMsg2) = abi.decode(_composeMsg, (uint32, bytes32, bytes));
            IHopComposer(_recipientAddress).hopCompose(srcEid, srcAddress, __oft, _amount, _composeMsg2);
        }
        emit Hop(__oft, _recipientAddress, _amount);
    }


    // Owner functions
    function setMessageProcessed(address oft, uint64 nonce, bytes32 _fraxtalHop) external onlyOwner {
        bytes32 messageHash = keccak256(abi.encodePacked(oft,  nonce, _fraxtalHop));
        emit MessageHash(oft, nonce, _fraxtalHop);
        messageProcessed[messageHash] = true;
    }       
}
