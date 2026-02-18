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
    address composerProxy = 0xF7c1a390f77B294c107Ca4204BffdC1a9Fae72F9; // FraxtalLZCurveComposer proxy
    uint256 amount = 1e13;
    string baseRpc = "https://base-rpc.publicnode.com";

    function run() external broadcaster {
        // https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 100_000, 0);
        // bytes memory options = OptionsBuilder.newOptions();
        /// @dev fails when second argument too high
        bytes memory composeMsg = abi.encode(0xb0E1650A9760e0f383174af042091fc544b8356f, uint256(0));
        SendParam memory sendParam = SendParam({
            dstEid: uint32(30255), // fraxtal
            to: addressToBytes32(composerProxy),
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
