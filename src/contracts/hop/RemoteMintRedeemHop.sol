// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IOFT2 } from "./interfaces/IOFT2.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ILayerZeroDVN } from "./interfaces/ILayerZeroDVN.sol";
import { ILayerZeroTreasury } from "./interfaces/ILayerZeroTreasury.sol";
import { IExecutor } from "./interfaces/IExecutor.sol";
import { console } from "frax-std/FraxTest.sol";

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
contract RemoteMintRedeemHop is Ownable {
    bool public paused = false;
    bytes32 public fraxtalHop;
    uint256 public noDNVs = 2;
    uint256 public hopFee = 1; // 10000 based so 1 = 0.01%

    address public immutable EXECUTOR;
    address public immutable DVN;
    address public immutable TREASURY;
    uint32 public immutable EID;



    event MintRedeem(address oft, address indexed sender, uint256 amountLD);

    error InvalidOApp();
    error HopPaused();
    error NotEndpoint();
    error InsufficientFee();

    constructor(bytes32 _fraxtalHop, uint256 _noDNVs, address _EXECUTOR, address _DVN, address _TREASURY, uint32 _EID) Ownable(msg.sender) {
        fraxtalHop = _fraxtalHop;
        noDNVs = _noDNVs;
        EXECUTOR = _EXECUTOR;
        DVN = _DVN;
        TREASURY = _TREASURY;
        EID = _EID;
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

    function setHopFee(uint256 _hopFee) external onlyOwner {
        hopFee = _hopFee;
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    // receive ETH
    receive() external payable {}

    function mintRedeem(
        address oft,
        uint256 _amountLD
    ) external payable {
        if (paused) revert HopPaused();
        SafeERC20.safeTransferFrom(IERC20(oft), msg.sender, address(this), _amountLD);
        _mintRedeemViaFraxtal(oft, bytes32(uint256(uint160(msg.sender))), _amountLD);

        emit MintRedeem(oft, msg.sender, _amountLD);
    }

    function _mintRedeemViaFraxtal(
        address _oft,
        bytes32 _to,
        uint256 _amountLD
    ) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: removeDust(_oft, _amountLD)
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        uint256 finalFee = fee.nativeFee + quoteHop();
        if (finalFee > msg.value) revert InsufficientFee();
        // Send the oft
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));

        // Refund the excess
        if (msg.value>finalFee) payable(msg.sender).transfer(msg.value - finalFee);
    }

    function _generateSendParam(
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) internal view returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        options = OptionsBuilder.addExecutorLzComposeOption(options,0,1000000,0);
        sendParam.dstEid = 30255;
        sendParam.to = fraxtalHop;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        sendParam.extraOptions = options;
        sendParam.composeMsg = abi.encode(_to, EID);
    }

    function quote(address oft,
        bytes32 _to,
        uint256 _amountLD) public view returns (MessagingFee memory fee) {
        SendParam memory sendParam = _generateSendParam({
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: removeDust(oft, _amountLD)
        });
        fee = IOFT(oft).quoteSend(sendParam, false);
        fee.nativeFee += quoteHop();
    }

    function quoteHop() public view returns (uint256 finalFee) {
        uint256 dvnFee = ILayerZeroDVN(DVN).getFee(EID, 5, address(this), "");
        bytes memory options = hex"010011010000000000000000000000000007A120";
        uint256 executorFee = IExecutor(EXECUTOR).getFee(EID, address(this), 40, options);
        uint256 totalFee = dvnFee * noDNVs + executorFee;
        uint256 treasuryFee = ILayerZeroTreasury(TREASURY).getFee(address(this), EID, totalFee, false);
        finalFee = totalFee + treasuryFee;
        finalFee = finalFee * (10000 + hopFee) / 10000;
    }

    function removeDust(address oft, uint256 _amountLD) internal view returns (uint256) {
        uint256 decimalConversionRate = IOFT2(oft).decimalConversionRate();
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }     
}
