// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Test contract to batch send (s)frxUSD from Fraxtal to chain X
contract BatchSend is Ownable {
    address public constant frxUsd = 0xFc00000000000000000000000000000000000001;
    address public constant sfrxUsd = 0xfc00000000000000000000000000000000000008;
    address public constant frxUsdLockbox = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address public constant sfrxUsdLockbox = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    function batchSend(
        uint256 frxUsdAmount,
        uint256 sfrxUsdAmount,
        uint32 frxUsdDstEid,
        uint32 sfrxUsdDstEid
    ) external payable onlyOwner {
        // transfer in token
        IERC20(frxUsd).transferFrom(msg.sender, address(this), frxUsdAmount);
        IERC20(sfrxUsd).transferFrom(msg.sender, address(this), sfrxUsdAmount);

        // approve lockbox to transfer amounts
        IERC20(frxUsd).approve(frxUsdLockbox, frxUsdAmount);
        IERC20(sfrxUsd).approve(sfrxUsdLockbox, sfrxUsdAmount);

        // send tokens
        _send({ _oft: frxUsdLockbox, _amountLD: frxUsdAmount, _dstEid: frxUsdDstEid });
        _send({ _oft: sfrxUsdLockbox, _amountLD: sfrxUsdAmount, _dstEid: sfrxUsdDstEid });
    }

    function _send(address _oft, uint256 _amountLD, uint32 _dstEid) internal {
        SendParam memory sendParam = _generateSendParam(_amountLD, _dstEid);
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));
    }

    function _generateSendParam(uint256 _amountLD, uint32 _dstEid) internal view returns (SendParam memory sendParam) {
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _amountLD;
        sendParam.dstEid = _dstEid;
        bytes memory options = OptionsBuilder.newOptions();
        sendParam.extraOptions = options;
        sendParam.to = bytes32(uint256(uint160(msg.sender)));
    }

    function recoverETH() external onlyOwner {
        payable(msg.sender).call{ value: address(this).balance }("");
    }

    function recoverToken(address token) external onlyOwner {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }
}
