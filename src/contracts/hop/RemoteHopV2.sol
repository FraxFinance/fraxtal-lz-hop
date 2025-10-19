// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { ILayerZeroDVN } from "src/contracts/hop/interfaces/ILayerZeroDVN.sol";
import { ILayerZeroTreasury } from "src/contracts/hop/interfaces/ILayerZeroTreasury.sol";
import { IExecutor } from "src/contracts/hop/interfaces/IExecutor.sol";

import { HopV2, HopMessage } from "src/contracts/hop/HopV2.sol";

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
contract RemoteHopV2 is HopV2, IOAppComposer {
    uint32 internal constant FRAXTAL_EID = 30255;

    struct RemoteHopV2Storage {
        uint32 numDVNs;
        uint256 hopFee; // 10_000 based so 1 = 0.01%
        mapping(uint32 eid => bytes options) executorOptions;
        address EXECUTOR;
        address DVN;
        address TREASURY;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.RemoteHopV2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RemoteHopV2StorageLocation = 
        0x092e031a5530f7fcb3ff5e857b626b93fc7001a81b918f0ab9aa9078c572b700;

    function _getRemoteHopV2Storage() private pure returns (RemoteHopV2Storage storage $) {
        assembly {
            $.slot := RemoteHopV2StorageLocation
        }
    }

    event Hop(address oft, address indexed recipient, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint32 _localEid,
        address _endpoint,
        bytes32 _fraxtalHop,
        uint32 _numDVNs,
        address _EXECUTOR,
        address _DVN,
        address _TREASURY,
        address[] memory _approvedOfts
    ) external initializer {
        __init_HopV2(_localEid, _endpoint, _approvedOfts);
        _setRemoteHop(FRAXTAL_EID, _fraxtalHop);

        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        $.numDVNs = _numDVNs;
        $.EXECUTOR = _EXECUTOR;
        $.DVN = _DVN;
        $.TREASURY = _TREASURY;
    }

    function setNumDVNs(uint32 _numDVNs) external onlyOwner {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        $.numDVNs = _numDVNs;
    }

    function setHopFee(uint256 _hopFee) external onlyOwner {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        $.hopFee = _hopFee;
    }

    function setExecutorOptions(uint32 eid, bytes memory _options) external onlyOwner {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        $.executorOptions[eid] = _options;
    }

    // receive ETH
    receive() external payable {}

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
            sendParam.to = remoteHop(FRAXTAL_EID); 

            bytes memory options = OptionsBuilder.newOptions();
            if (_hopMessage.dstGas < 400_000) _hopMessage.dstGas = 400_000;
            uint128 fraxtalGas = 1_000_000;
            if (_hopMessage.dstGas > fraxtalGas && _hopMessage.dstEid == FRAXTAL_EID) fraxtalGas = _hopMessage.dstGas;
            options = OptionsBuilder.addExecutorLzComposeOption(options, 0, fraxtalGas, 0);
            sendParam.extraOptions = options;

            sendParam.composeMsg = abi.encode(_hopMessage);
        }
    }

    function quoteHop(uint32 _dstEid, uint128 _dstGas, bytes memory _data) public view override returns (uint256 finalFee) {
        // No hop needed if Fraxtal is the destination
        if (_dstEid == FRAXTAL_EID) return 0;
        
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();

        uint256 dvnFee = ILayerZeroDVN($.DVN).getFee(_dstEid, 5, address(this), "");
        bytes memory options = $.executorOptions[_dstEid];
        if (options.length == 0) options = hex"01001101000000000000000000000000000493E0";
        if (_data.length != 0) {
            if (_dstGas < 400_000) _dstGas = 400_000;
            options = abi.encodePacked(options,hex"010013030000", _dstGas);
        }
        uint256 executorFee = IExecutor($.EXECUTOR).getFee(_dstEid, address(this), 36, options);
        uint256 totalFee = dvnFee * $.numDVNs + executorFee;
        uint256 treasuryFee = ILayerZeroTreasury($.TREASURY).getFee(address(this), _dstEid, totalFee, false);
        finalFee = totalFee + treasuryFee;
        finalFee = (finalFee * (10_000 + $.hopFee)) / 10_000;
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
        (bool isTrustedHopMessage, bool isDuplicateMessage) = _validateComposeMessage(_oft, _message);
        if (isDuplicateMessage) return;

        // Extract the composed message from the delivered message using the MsgCodec
        (HopMessage memory hopMessage) = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (HopMessage));
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        
        if (!isTrustedHopMessage) {
            hopMessage.srcEid = OFTComposeMsgCodec.srcEid(_message);
            hopMessage.sender = OFTComposeMsgCodec.composeFrom(_message);
        }

        _sendLocal({
            _oft: _oft,
            _amount: amount,
            _isTrustedHopMessage: isTrustedHopMessage,
            _hopMessage: hopMessage
        });

        emit Hop(_oft, address(uint160(uint256(hopMessage.recipient))), amount);
    }

    function numDVNs() external view returns (uint32) {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        return $.numDVNs;
    }

    function hopFee() external view returns (uint256) {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        return $.hopFee;
    }

    function executorOptions(uint32 eid) external view returns (bytes memory) {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        return $.executorOptions[eid];
    }

    function EXECUTOR() external view returns (address) {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        return $.EXECUTOR;
    }

    function DVN() external view returns (address) {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        return $.DVN;
    }

    function TREASURY() external view returns (address) {
        RemoteHopV2Storage storage $ = _getRemoteHopV2Storage();
        return $.TREASURY;
    }

}
