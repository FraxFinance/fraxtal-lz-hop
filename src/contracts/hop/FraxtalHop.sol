// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IOFT2 } from "./interfaces/IOFT2.sol";
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
contract FraxtalHop is Ownable2Step, IOAppComposer {
    address public constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    address public constant frxUsdLockbox = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address public constant sfrxUsdLockbox = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address public constant frxEthLockbox = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address public constant sfrxEthLockbox = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address public constant fxsLockbox = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address public constant fpiLockbox = 0x75c38D46001b0F8108c4136216bd2694982C20FC;

    bool public paused = false;
    mapping(uint32 => bytes32) public remoteHop;
    mapping(bytes32 => bool) public messageProcessed;

    event Hop(address oft, uint32 indexed srcEid, uint32 indexed dstEid, bytes32 indexed recipient, uint256 amount);
    event MessageHash(address oft, uint32 indexed srcEid, uint64 indexed nonce, bytes32 indexed composeFrom);

    error InvalidOFT();
    error HopPaused();
    error NotEndpoint();
    error InvalidSourceChain();
    error InvalidSourceHop();

    constructor() Ownable(msg.sender) {}

    // Admin functions
    function recoverERC20(address tokenAddress, address recipient, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(recipient, tokenAmount);
    }

    function recoverETH(address recipient, uint256 tokenAmount) external onlyOwner {
        payable(recipient).transfer(tokenAmount);
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
        if (
            _oft != frxUsdLockbox &&
            _oft != sfrxUsdLockbox &&
            _oft != frxEthLockbox &&
            _oft != sfrxEthLockbox &&
            _oft != fxsLockbox &&
            _oft != fpiLockbox
        ) {
            revert InvalidOFT();
        }

        uint32 srcEid = OFTComposeMsgCodec.srcEid(_message);
        {
            bytes32 composeFrom = OFTComposeMsgCodec.composeFrom(_message);
            uint64 nonce = OFTComposeMsgCodec.nonce(_message);
            bytes32 messageHash = keccak256(abi.encodePacked(_oft, srcEid, nonce, composeFrom));

            emit MessageHash(_oft, srcEid, nonce, composeFrom);
            // Avoid duplicated messages
            if (!messageProcessed[messageHash]) {
                messageProcessed[messageHash] = true;
            } else {
                return;
            }
            if (remoteHop[srcEid] == bytes32(0)) revert InvalidSourceChain();
            if (remoteHop[srcEid] != composeFrom) revert InvalidSourceHop();
        }

        // Extract the composed message from the delivered message using the MsgCodec
        (bytes32 recipient, uint32 _dstEid) = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (bytes32, uint32));
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        if (_dstEid == 30255) {
            SafeERC20.safeTransfer(IERC20(IOFT(_oft).token()), address(uint160(uint256(recipient))), amount);
        } else {
            SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, amount);
            _send({ _oft: address(_oft), _dstEid: _dstEid, _to: recipient, _amountLD: amount });
        }
        emit Hop(_oft, srcEid, _dstEid, recipient, amount);
    }

    function _send(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: removeDust(_oft, _amountLD)
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        // Send the oft
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));
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

    function quote(
        address oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD
    ) public view returns (MessagingFee memory fee) {
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: removeDust(oft, _amountLD)
        });
        fee = IOFT(oft).quoteSend(sendParam, false);
    }

    function removeDust(address oft, uint256 _amountLD) internal view returns (uint256) {
        uint256 decimalConversionRate = IOFT2(oft).decimalConversionRate();
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }

    // Owner functions
    function setMessageProcessed(address oft, uint32 srcEid, uint64 nonce, bytes32 composeFrom) external onlyOwner {
        bytes32 messageHash = keccak256(abi.encodePacked(oft, srcEid, nonce, composeFrom));
        emit MessageHash(oft, srcEid, nonce, composeFrom);
        messageProcessed[messageHash] = true;
    }
}
