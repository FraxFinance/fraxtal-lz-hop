// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOFT2 } from "./interfaces/IOFT2.sol";
import { ILayerZeroDVN } from "./interfaces/ILayerZeroDVN.sol";
import { ILayerZeroTreasury } from "./interfaces/ILayerZeroTreasury.sol";
import { IExecutor } from "./interfaces/IExecutor.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ============================ RemoteHop =============================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract RemoteHop is Ownable {
    bool public paused = false;
    bytes32 public fraxtalHop;
    uint256 public noDNVs = 2;

    address public immutable EXECUTOR;
    address public immutable DVN;
    address public immutable TREASURY;

    error InvalidOApp();
    error HopPaused();
    error NotEndpoint();
    error InsufficientFee();

    constructor(bytes32 _fraxtalHop, uint256 _noDNVs, address _EXECUTOR, address _DVN, address _TREASURY) Ownable(msg.sender) {
        fraxtalHop = _fraxtalHop;
        noDNVs = _noDNVs;
        EXECUTOR = _EXECUTOR;
        DVN = _DVN;
        TREASURY = _TREASURY;
    }

    // Admin functions
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    }

    function recoverETH(uint256 tokenAmount) external onlyOwner {
        payable(msg.sender).transfer(tokenAmount);
    }

    function setFraxtalHop(address _fraxtalHop) external {
        setFraxtalHop(bytes32(uint256(uint160(_fraxtalHop))));
    }

    function setFraxtalHop(bytes32 _fraxtalHop) public onlyOwner {
        fraxtalHop = _fraxtalHop;
    }

    function setNoDNVs(uint256 _noDNVs) external onlyOwner {
        noDNVs = _noDNVs;
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    // receive ETH
    receive() external payable {}

    function sendOFT(
        address oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD
    ) external {
        if (paused) revert HopPaused();
        if (_dstEid==30255) revert NotEndpoint();
        SafeERC20.safeTransferFrom(IERC20(oft), msg.sender, address(this), _amountLD);
        _sendViaFraxtal(oft, _dstEid, _to, _amountLD);
    }

    function _sendViaFraxtal(
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
        if (fee.nativeFee + quoteHop(_oApp, _dstEid) > msg.value) revert InsufficientFee();
        // Send the oft
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, address(this));
    }

    function _generateSendParam(
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) internal view returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        sendParam.dstEid = 30255;
        sendParam.to = fraxtalHop;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        sendParam.extraOptions = options;
        sendParam.composeMsg = abi.encode(_to, _dstEid);
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
        fee.nativeFee += quoteHop(oft, _dstEid);
    }

    function quoteHop(address oft, uint32 _dstEid) public view returns (uint256 finalFee) {
        bytes memory options = IOFT2(oft).combineOptions(_dstEid, 1, OptionsBuilder.newOptions());
        uint256 dvnFee = ILayerZeroDVN(DVN).getFee(_dstEid, 5, address(this), "");
        options = hex"0100110100000000000000000000000000030d40";
        uint256 executorFee = IExecutor(EXECUTOR).getFee(_dstEid, address(this), 40, options);
        uint256 totalFee = dvnFee * noDNVs + executorFee;
        uint256 treasuryFee = ILayerZeroTreasury(TREASURY).getFee(address(this), _dstEid, totalFee, false);
        finalFee = totalFee + treasuryFee;
    }
}
