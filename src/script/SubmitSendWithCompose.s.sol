// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SubmitSendWithCompose is BaseScript {
    using OptionsBuilder for bytes;

    address oft = 0x909DBdE1eBE906Af95660033e478D59EFe831fED; // Base FRAX OFT
    address swapMock = 0xbA5797448733D4691A1f20b26c5Cf5CE02E52a57; // Fraxtal MockReceiver
    uint256 amount = 1e15;
    string baseRpc = "https://base-rpc.publicnode.com";

    function run() external {
        address token = IOFT(oft).token();
        IERC20(token).approve(oft, type(uint256).max);

        // https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 1_000_000, 0);
        bytes memory options = OptionsBuilder.newOptions();
        bytes memory composeMsg = abi.encode(swapMock);
        SendParam memory sendParam = SendParam({
            dstEid: uint32(30255), // fraxtal
            to: addressToBytes32(swapMock),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: '',
            oftCmd: ''
        });
        MessagingFee memory fee = IOFT(oft).quoteSend(sendParam, false);
        IOFT(oft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(vm.addr(privateKey))
        );
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}