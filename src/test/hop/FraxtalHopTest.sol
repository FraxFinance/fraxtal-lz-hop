// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../BaseTest.t.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { FraxtalHop } from "src/contracts/hop/FraxtalHop.sol";
import { RemoteHop } from "src/contracts/hop/RemoteHop.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FraxtalHopTest is BaseTest {
    FraxtalHop hop;
    RemoteHop remoteHop;
    address constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant EXECUTOR = 0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d;
    address constant DVN = 0xcCE466a522984415bC91338c232d98869193D46e;
    address constant TREASURY = 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821;
    address[] approvedOfts;

    // receive ETH
    receive() external payable {}

    function setUpFraxtal() public virtual {
        approvedOfts.push(0x96A394058E2b84A89bac9667B19661Ed003cF5D4);
        approvedOfts.push(0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361);
        approvedOfts.push(0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604);
        approvedOfts.push(0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168);
        approvedOfts.push(0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A);
        approvedOfts.push(0x75c38D46001b0F8108c4136216bd2694982C20FC);

        vm.createSelectFork(vm.envString("FRAXTAL_MAINNET_URL"), 17180177);
        hop = new FraxtalHop(approvedOfts);
        remoteHop = new RemoteHop(
            address(1),
            OFTMsgCodec.addressToBytes32(address(hop)),
            2,
            EXECUTOR,
            DVN,
            TREASURY,
            approvedOfts
        );
        hop.setRemoteHop(30110, address(remoteHop));
        remoteHop.setFraxtalHop(address(hop));
        payable(address(hop)).call{ value: 1 ether }("");
    }

    function setupArbitrum() public {
        approvedOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df);
        approvedOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0);
        approvedOfts.push(0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050);
        approvedOfts.push(0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45);
        approvedOfts.push(0x64445f0aecC51E94aD52d8AC56b7190e764E561a);
        approvedOfts.push(0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927);

        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_URL"), 316670752);
        hop = new FraxtalHop(approvedOfts);
        remoteHop = new RemoteHop(
            address(1), // owner
            OFTMsgCodec.addressToBytes32(address(hop)),
            2,
            0x31CAe3B7fB82d847621859fb1585353c5720660D,
            0x2f55C492897526677C5B68fb199ea31E2c126416,
            0x532410B245eB41f24Ed1179BA0f6ffD94738AE70,
            approvedOfts
        );
    }

    function setupEthereum() public {
        approvedOfts.push(0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0);
        approvedOfts.push(0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126);
        approvedOfts.push(0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6);
        approvedOfts.push(0xbBc424e58ED38dd911309611ae2d7A23014Bd960);
        approvedOfts.push(0xC6F59a4fD50cAc677B51558489E03138Ac1784EC);
        approvedOfts.push(0x9033BAD7aA130a2466060A2dA71fAe2219781B4b);

        vm.createSelectFork(vm.envString("ETHEREUM_MAINNET_URL"), 22124047);
        hop = new FraxtalHop(approvedOfts);
        remoteHop = new RemoteHop(
            address(1), // owner
            OFTMsgCodec.addressToBytes32(address(hop)),
            2,
            0x173272739Bd7Aa6e4e214714048a9fE699453059,
            0x589dEDbD617e0CBcB916A9223F4d1300c294236b,
            0x5ebB3f2feaA15271101a927869B3A56837e73056,
            approvedOfts
        );
    }

    function test_lzCompose() public {
        setUpFraxtal();
        address _oApp = address(0x96A394058E2b84A89bac9667B19661Ed003cF5D4);
        address frxUSD = address(0xFc00000000000000000000000000000000000001);
        deal(frxUSD, address(hop), 1e18);
        bytes memory _composeMsg = abi.encode(OFTMsgCodec.addressToBytes32(address(this)), 30332);
        _composeMsg = abi.encodePacked(OFTMsgCodec.addressToBytes32(address(remoteHop)), _composeMsg);
        bytes memory _msg = OFTComposeMsgCodec.encode(
            0, // nonce of the origin transaction
            30110, // source endpoint id of the transaction
            1e18, // the token amount in local decimals to credit
            _composeMsg // the composed message
        );
        uint gasStart = gasleft();
        vm.startPrank(ENDPOINT);
        hop.lzCompose(_oApp, bytes32(0), _msg, address(0), "");
        vm.stopPrank();
        console.log("Gas used:", gasStart - gasleft());
    }

    function test_RemoteHop_quoteHop() public {
        setupArbitrum();
        address _oApp = address(0x80Eede496655FB9047dd39d9f418d5483ED600df);
        MessagingFee memory fee = remoteHop.quote(_oApp, 30332, OFTMsgCodec.addressToBytes32(address(this)), 1e18);
        console.log(fee.nativeFee, fee.lzTokenFee);
        uint256 quoteHop = remoteHop.quoteHop(30332);
        console.log(quoteHop);
    }

    // Send from Arbitrum to Sonic
    function test_RemoteHop_sendOFT() public {
        setupArbitrum();
        address _oApp = address(0x80Eede496655FB9047dd39d9f418d5483ED600df);
        deal(_oApp, address(this), 1e18);
        IERC20(_oApp).approve(address(remoteHop), 1e18);
        MessagingFee memory fee = remoteHop.quote(_oApp, 30332, OFTMsgCodec.addressToBytes32(address(this)), 1e18);
        uint256 balance = payable(this).balance;
        remoteHop.sendOFT{ value: fee.nativeFee + 0.1E18 }(
            _oApp,
            30332,
            OFTMsgCodec.addressToBytes32(address(this)),
            1e18
        );
        uint256 balance2 = payable(this).balance;
        assertEq(balance - balance2, fee.nativeFee);
    }

    // Send from Arbitrum to Fraxtal
    function test_RemoteHop_sendOFT_toFraxtal() public {
        setupArbitrum();
        address _oApp = address(0x80Eede496655FB9047dd39d9f418d5483ED600df);
        deal(_oApp, address(this), 1e18);
        IERC20(_oApp).approve(address(remoteHop), 1e18);
        MessagingFee memory fee = remoteHop.quote(_oApp, 30255, OFTMsgCodec.addressToBytes32(address(this)), 1e18);
        uint256 balance = payable(this).balance;
        remoteHop.sendOFT{ value: fee.nativeFee + 0.1E18 }(
            _oApp,
            30255,
            OFTMsgCodec.addressToBytes32(address(this)),
            1e18
        );
        uint256 balance2 = payable(this).balance;
        assertEq(balance - balance2, fee.nativeFee);
    }

    function test_RemoteHop_quoteHop2() public {
        setupEthereum();
        address _oApp = address(0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0);
        MessagingFee memory fee = remoteHop.quote(_oApp, 30332, OFTMsgCodec.addressToBytes32(address(this)), 1e18);
        console.log(fee.nativeFee, fee.lzTokenFee);
        uint256 quoteHop = remoteHop.quoteHop(30332);
        console.log(quoteHop);
    }

    // Send from Ethereum to Sonic
    function test_RemoteHop_sendOFT2() public {
        setupEthereum();
        address _oApp = address(0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0);
        IERC20 erc20 = IERC20(0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29);
        deal(address(erc20), address(this), 1e18);
        IERC20(erc20).approve(address(remoteHop), 1e18);
        MessagingFee memory fee = remoteHop.quote(_oApp, 30332, OFTMsgCodec.addressToBytes32(address(this)), 1e18);
        uint256 balance = payable(this).balance;
        remoteHop.sendOFT{ value: fee.nativeFee + 0.1E18 }(
            _oApp,
            30332,
            OFTMsgCodec.addressToBytes32(address(this)),
            1e18
        );
        uint256 balance2 = payable(this).balance;
        assertEq(balance - balance2, fee.nativeFee);
    }
}
