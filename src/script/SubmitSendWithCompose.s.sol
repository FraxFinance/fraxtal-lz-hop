// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SubmitSendWithCompose is BaseScript {
    using OptionsBuilder for bytes;

    // address oft = 0x909DBdE1eBE906Af95660033e478D59EFe831fED; // Base FRAX OFT
    address oft = 0xF010a7c8877043681D59AD125EbF575633505942; // Base frxETH OFT
    address swapMock = 0x60356998558A466Ec51BdE7e78F3b88Bdc843c5e; // Fraxtal MockReceiver
    uint256 amount = 1e13;
    string baseRpc = "https://base-rpc.publicnode.com";

    function run() external broadcaster {
        // https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 1_000_000, 0);
        // bytes memory options = OptionsBuilder.newOptions();
        /// @dev: fails when second argument too high
        bytes memory composeMsg = abi.encode(0xb0E1650A9760e0f383174af042091fc544b8356f, uint256(0));
        SendParam memory sendParam = SendParam({
            dstEid: uint32(30255), // fraxtal
            to: addressToBytes32(swapMock),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(oft).quoteSend(sendParam, false);
        IOFT(oft).send{ value: fee.nativeFee }(sendParam, fee, payable(vm.addr(privateKey)));
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
