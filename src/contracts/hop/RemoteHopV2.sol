// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ILayerZeroDVN } from "./interfaces/ILayerZeroDVN.sol";
import { ILayerZeroTreasury } from "./interfaces/ILayerZeroTreasury.sol";
import { IExecutor } from "./interfaces/IExecutor.sol";
import { IHopComposer } from "./interfaces/IHopComposer.sol";
import { IHopV2, HopMessage } from "./interfaces/IHopV2.sol";

import { HopV2 } from "src/contracts/hop/HopV2.sol";

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
contract RemoteHopV2 is HopV2, IOAppComposer, IHopV2 {
    uint32 constant FRAXTAL_EID = 30255;
    uint256 public numDVNs = 2;
    uint256 public hopFee = 1; // 10000 based so 1 = 0.01%
    mapping(uint32 => bytes) public executorOptions;

    address public immutable EXECUTOR;
    address public immutable DVN;
    address public immutable TREASURY;

    event SendOFT(address oft, address indexed sender, uint32 indexed dstEid, bytes32 indexed to, uint256 amountLD);
    event Hop(address oft, address indexed recipient, uint256 amount);

    error ZeroAmountSend();

    constructor(
        bytes32 _fraxtalHop,
        uint256 _numDVNs,
        address _EXECUTOR,
        address _DVN,
        address _TREASURY,
        address[] memory _approvedOfts
    ) HopV2(_EXECUTOR, _approvedOfts) {
        remoteHop[FRAXTAL_EID] = _fraxtalHop;
        numDVNs = _numDVNs;
        EXECUTOR = _EXECUTOR;
        DVN = _DVN;
        TREASURY = _TREASURY;
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

    // receive ETH
    receive() external payable {}

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD) external payable {
        sendOFT(_oft, _dstEid, _to, _amountLD, 0, "");
    }

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD, uint128 _dstGas, bytes memory _data) public payable {
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();
        _amountLD = removeDust(_oft, _amountLD);

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: localEid,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        // Transfer the OFT token to the hop
        if (_amountLD > 0) SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);

        uint256 sendFee;
        if (_dstEid == localEid) {
            // Sending from src => src: no LZ send needed
            _sendLocal(_oft, _amountLD, hopMessage);
        } else {
            sendFee = _sendToDestination(_oft, _amountLD, true, hopMessage);
        }

        // validate the msg.value
        _handleMsgValue(sendFee);

        emit SendOFT(_oft, msg.sender, _dstEid, _recipient, _amountLD);
    }

    function _generateSendParam(
        uint256 _amountLD,
        HopMessage memory _hopMessage
    ) internal view override returns (SendParam memory sendParam) {
        sendParam.dstEid = FRAXTAL_EID;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _amountLD;
        if (_hopMessage.dstEid == FRAXTAL_EID && _hopMessage.data.length == 0) { 
            // Send directly to Fraxtal, no compose needed
            sendParam.to = _hopMessage.recipient;
        } else {
            sendParam.to = remoteHop[FRAXTAL_EID]; 

            bytes memory options = OptionsBuilder.newOptions();
            if (_hopMessage.dstGas < 400000) _hopMessage.dstGas = 400000;
            uint128 fraxtalGas = 1000000;
            if (_hopMessage.dstGas > fraxtalGas && _hopMessage.dstEid == FRAXTAL_EID) fraxtalGas = _hopMessage.dstGas;
            options = OptionsBuilder.addExecutorLzComposeOption(options, 0, fraxtalGas, 0);
            sendParam.extraOptions = options;

            sendParam.composeMsg = abi.encode(_hopMessage);
        }
    }

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) public view returns (uint256) {
        if (_dstEid == localEid) return 0;
        _amountLD = removeDust(_oft, _amountLD);

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: localEid,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        SendParam memory sendParam = _generateSendParam({
            _hopMessage: hopMessage,
            _amountLD: _amountLD
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        fee.nativeFee += quoteHop(_dstEid, _dstGas, _data);
        return fee.nativeFee;
    }

    function quoteHop(uint32 _dstEid, uint128 _dstGas, bytes memory _data) public view override returns (uint256 finalFee) {
        uint256 dvnFee = ILayerZeroDVN(DVN).getFee(_dstEid, 5, address(this), "");
        bytes memory options = executorOptions[_dstEid];
        if (options.length == 0) options = hex"01001101000000000000000000000000000493E0";
        if (_data.length != 0) {
            if (_dstGas < 400000) _dstGas = 400000;
            options = abi.encodePacked(options,hex"010013030000", _dstGas);
        }
        uint256 executorFee = IExecutor(EXECUTOR).getFee(_dstEid, address(this), 36, options);
        uint256 totalFee = dvnFee * numDVNs + executorFee;
        uint256 treasuryFee = ILayerZeroTreasury(TREASURY).getFee(address(this), _dstEid, totalFee, false);
        finalFee = totalFee + treasuryFee;
        finalFee = (finalFee * (10000 + hopFee)) / 10000;
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
        (, bool isDuplicateMessage) = _validateComposeMessage(_oft, _message);
        if (isDuplicateMessage) return;

        // Extract the composed message from the delivered message using the MsgCodec
        HopMessage memory hopMessage = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (HopMessage));
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        
        _sendLocal(_oft, amount, hopMessage);

        emit Hop(_oft, address(uint160(uint256(hopMessage.recipient))), amount);
    }  
}
