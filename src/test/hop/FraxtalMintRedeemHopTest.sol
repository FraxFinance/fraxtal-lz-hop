// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../BaseTest.t.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { FraxtalMintRedeemHop } from "src/contracts/hop/FraxtalMintRedeemHop.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FraxtalMintRedeemHopTest2 is BaseTest {
    FraxtalMintRedeemHop hop;
    RemoteMintRedeemHop remoteHop;
    address constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant EXECUTOR = 0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d;
    address constant DVN = 0xcCE466a522984415bC91338c232d98869193D46e;
    address constant TREASURY = 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821;

    // receive ETH
    receive() external payable {}

    function setUpFraxtal() public virtual {
        vm.createSelectFork(vm.envString("FRAXTAL_MAINNET_URL"), 17180177);
        hop = new FraxtalMintRedeemHop();
        remoteHop = new RemoteMintRedeemHop(OFTMsgCodec.addressToBytes32(address(hop)), 2, EXECUTOR, DVN, TREASURY, 30255);
        hop.setRemoteHop(30110, address(remoteHop));
        remoteHop.setFraxtalHop(address(hop));
        payable(address(hop)).transfer(1 ether);
    }

    function setupArbitrum() public {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_URL"), 316670752);
        hop = new FraxtalMintRedeemHop();
        remoteHop = new RemoteMintRedeemHop(OFTMsgCodec.addressToBytes32(address(hop)), 2, 0x31CAe3B7fB82d847621859fb1585353c5720660D, 0x2f55C492897526677C5B68fb199ea31E2c126416, 0x532410B245eB41f24Ed1179BA0f6ffD94738AE70,30110);
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
        MessagingFee memory fee = remoteHop.quote(_oApp,OFTMsgCodec.addressToBytes32(address(this)),1e18);
        console.log(fee.nativeFee, fee.lzTokenFee);
        uint256 quoteHop = remoteHop.quoteHop();
        console.log(quoteHop);
    }

    // Send from Arbitrum to Sonic
    function test_RemoteHop_sendOFT() public {
        setupArbitrum();
        address _oApp = address(0x80Eede496655FB9047dd39d9f418d5483ED600df);
        deal(_oApp, address(this), 1e18);
        IERC20(_oApp).approve(address(remoteHop), 1e18);
        MessagingFee memory fee = remoteHop.quote(_oApp,OFTMsgCodec.addressToBytes32(address(this)),1e18);
        uint256 balance = payable(this).balance;
        remoteHop.mintRedeem{value:fee.nativeFee+0.1E18}(_oApp,1e18);
        uint256 balance2 = payable(this).balance;
        assertEq(balance-balance2,fee.nativeFee);
    }    
}