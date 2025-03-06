// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ============================ FraxtalHop ============================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract FraxtalHop is Ownable, IOAppComposer {
    address constant endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    bool public paused = false;
    mapping(uint32 => bytes32) public remoteHop;

    error InvalidOApp();
    error HopPaused();
    error NotEndpoint();
    error InvalidSourceChain();
    error InvalidSourceHop();

    constructor() Ownable(msg.sender) {
    }

    // Admin functions
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    }

    function recoverETH(uint256 tokenAmount) external onlyOwner {
        payable(msg.sender).transfer(tokenAmount);
    }

    function setRemoteHop(uint32 _eid, address _remoteHop) external {
        setRemoteHop(_eid, bytes32(uint256(uint160(_remoteHop))));
    }

    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) public onlyOwner {
        remoteHop[_eid] = _remoteHop;
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    // receive ETH
    receive() external payable {}

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a token swap.
    ///      This method expects the encoded compose message to contain the swap amount and recipient address.
    /// @dev source: https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
    /// @param _oApp The address of the originating OApp/Token.
    /// @param /*_guid*/ The globally unique identifier of the message
    /// @param _message The encoded message content in the format of the OFTComposeMsgCodec.
    /// @param /*Executor*/ Executor address
    /// @param /*Executor Data*/ Additional data for checking for a specific executor
    function lzCompose(
        address _oApp,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*Executor*/,
        bytes calldata /*Executor Data*/
    ) external payable override {
        if (msg.sender != endpoint) revert NotEndpoint();
        if (paused) revert HopPaused();
        uint32 srcEid = OFTComposeMsgCodec.srcEid(_message);
        if (remoteHop[srcEid]==bytes32(0)) revert InvalidSourceChain();
        if (remoteHop[srcEid]!=OFTComposeMsgCodec.composeFrom(_message)) revert InvalidSourceHop();

        // Extract the composed message from the delivered message using the MsgCodec
        (bytes32  recipient, uint32 _dstEid) = abi.decode(
            OFTComposeMsgCodec.composeMsg(_message),
            (bytes32, uint32)
        );
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        SafeERC20.forceApprove(IERC20(IOFT(_oApp).token()),_oApp, amount);
        _send({
            _oApp: address(_oApp),
            _dstEid: _dstEid,
            _to: recipient,
            _amountLD: amount
        });
    }

    function _send(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD
    ) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _amountLD
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        // Send the oft
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, address(this));
    }

    function _generateSendParam(
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) internal pure returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        sendParam.dstEid = _dstEid;
        sendParam.to = _to;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        sendParam.extraOptions = options;
    }

    function quote(address oft, 
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD) public view returns (MessagingFee memory fee) {
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _amountLD
        });
        fee = IOFT(oft).quoteSend(sendParam, false);
    }
}
