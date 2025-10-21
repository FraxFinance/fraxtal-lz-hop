// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IOFT2 } from "./interfaces/IOFT2.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
contract RemoteHop is Ownable2Step {
    bool public paused = false;
    bytes32 public fraxtalHop;
    uint256 public numDVNs = 2;
    uint256 public hopFee = 1; // 10000 based so 1 = 0.01%
    mapping(uint32 => bytes) public executorOptions;
    mapping(address => bool) public approvedOft;

    address public immutable EXECUTOR;
    address public immutable DVN;
    address public immutable TREASURY;

    event SendOFT(address oft, address indexed sender, uint32 indexed dstEid, bytes32 indexed to, uint256 amountLD);

    error InvalidOFT();
    error HopPaused();
    error NotEndpoint();
    error InsufficientFee();
    error RefundFailed();
    error ZeroAmountSend();
    error ArrayLengthMismatch();

    function version() external pure virtual returns (string memory) {
        return "1.0.1";
    }

    constructor(
        address _owner,
        bytes32 _fraxtalHop,
        uint256 _numDVNs,
        address _EXECUTOR,
        address _DVN,
        address _TREASURY,
        address[] memory _approvedOfts,
        uint32[] memory _eids,
        bytes[] memory _executorOptions
    ) Ownable(_owner) {
        fraxtalHop = _fraxtalHop;
        numDVNs = _numDVNs;
        EXECUTOR = _EXECUTOR;
        DVN = _DVN;
        TREASURY = _TREASURY;

        for (uint256 i = 0; i < _approvedOfts.length; i++) {
            approvedOft[_approvedOfts[i]] = true;
        }
        uint256 _eidCount = _eids.length;
        if (_eidCount != _executorOptions.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < _eidCount; i++) {
            executorOptions[_eids[i]] = _executorOptions[i];
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
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();

        _amountLD = removeDust(_oft, _amountLD);
        if (_amountLD == 0) revert ZeroAmountSend();
        SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);
        if (_dstEid == 30255) {
            _sendToFraxtal(_oft, _to, _amountLD);
        } else {
            _sendViaFraxtal(_oft, _dstEid, _to, _amountLD);
        }
        emit SendOFT(_oft, msg.sender, _dstEid, _to, _amountLD);
    }

    function _sendToFraxtal(address _oft, bytes32 _to, uint256 _amountLD) internal {
        // Send the oft
        SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, _amountLD);
        SendParam memory sendParam = SendParam({
            dstEid: 30255,
            to: _to,
            amountLD: _amountLD,
            minAmountLD: _amountLD,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));

        // Refund the excess
        if (msg.value < fee.nativeFee) revert InsufficientFee();
        if (msg.value > fee.nativeFee) {
            (bool success, ) = address(msg.sender).call{ value: msg.value - fee.nativeFee }("");
            if (!success) revert RefundFailed();
        }
    }

    function _sendViaFraxtal(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _amountLD
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        uint256 finalFee = fee.nativeFee + quoteHop(_dstEid);
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
        uint256 _minAmountLD
    ) internal view returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        options = OptionsBuilder.addExecutorLzComposeOption(options, 0, 1000000, 0);
        sendParam.dstEid = 30255;
        sendParam.to = fraxtalHop;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        sendParam.extraOptions = options;
        sendParam.composeMsg = abi.encode(_to, _dstEid);
    }

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD
    ) public view returns (MessagingFee memory fee) {
        _amountLD = removeDust(_oft, _amountLD);
        if (_dstEid == 30255) {
            SendParam memory sendParam = SendParam({
                dstEid: 30255,
                to: _to,
                amountLD: _amountLD,
                minAmountLD: _amountLD,
                extraOptions: "",
                composeMsg: "",
                oftCmd: ""
            });
            fee = IOFT(_oft).quoteSend(sendParam, false);
        } else {
            SendParam memory sendParam = _generateSendParam({
                _dstEid: _dstEid,
                _to: _to,
                _amountLD: _amountLD,
                _minAmountLD: _amountLD
            });
            fee = IOFT(_oft).quoteSend(sendParam, false);
            fee.nativeFee += quoteHop(_dstEid);
        }
    }

    function quoteHop(uint32 _dstEid) public view returns (uint256 finalFee) {
        uint256 dvnFee = ILayerZeroDVN(DVN).getFee(_dstEid, 5, address(this), "");
        bytes memory options = executorOptions[_dstEid];
        if (options.length == 0) options = hex"01001101000000000000000000000000000493E0";
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
}
