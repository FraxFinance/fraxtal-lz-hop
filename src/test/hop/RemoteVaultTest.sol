// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../BaseTest.t.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RemoteVaultHop } from "src/contracts/hop/RemoteVaultHop.sol";
import { RemoteVaultDeposit } from "src/contracts/hop/RemoteVaultDeposit.sol";

contract RemoteVaultTest is BaseTest {
    RemoteVaultHop remoteVaultHop;
    address frxUSD;
    address oft;
    address hop;


    receive() external payable {}

    function setupBase() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_URL"), 36482910);
        frxUSD = 0xe5020A6d073a794B6E7f05678707dE47986Fb0b6;
        oft = frxUSD;
        hop = 0x10f2773F54CA36d456d6513806aA24f5169D6765;
        uint32 eid = 30184;
        remoteVaultHop = new RemoteVaultHop(frxUSD, oft, hop, eid);
        remoteVaultHop.setRemoteVaultHop(30255, address(remoteVaultHop));
        remoteVaultHop.addRemoteVault(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2,"Fraxlend Interest Bearing frxUSD (Frax Share) - 9","ffrxUSD(FXS)-9");
    }

    function setupFraxtal() public {
        vm.createSelectFork(vm.envString("FRAXTAL_MAINNET_URL"), 26472666);
        frxUSD = 0xFc00000000000000000000000000000000000001;
        oft = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
        hop = 0xB0f86D71568047B80bc105D77C63F8a6c5AEB5a8;
        uint32 eid = 30255;
        remoteVaultHop = new RemoteVaultHop(frxUSD, oft, hop, eid);
        remoteVaultHop.setRemoteVaultHop(30184, address(remoteVaultHop));
        remoteVaultHop.setRemoteVaultHop(30255, address(remoteVaultHop));
        remoteVaultHop.addLocalVault(0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2,0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2);
    }

    function test_depositRedeem() public {
        setupBase();
        deal(frxUSD, address(this), 10E18);
        RemoteVaultDeposit depositToken = RemoteVaultDeposit(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2));
        vm.deal(address(this), 1E18);
        IERC20(frxUSD).approve(address(depositToken), type(uint256).max);
        uint256 fee  = remoteVaultHop.quote(10E18, 30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2);
        depositToken.deposit{value: fee}(10E18);
        uint256 balance = IERC20(depositToken).balanceOf(address(this));
        console.log("Balance of deposit tokens:", balance);

        RemoteVaultHop.RemoteVaultMessage memory message = RemoteVaultHop.RemoteVaultMessage({
            action: RemoteVaultHop.Action.DepositReturn,
            userEid: 30184,
            userAddress: address(this),
            remoteEid: 30255,
            remoteVault: 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2,
            amount: 8.85458600678413454E18,
            remoteTimestamp: 1759756961,
            pricePerShare: 885458600678000000
        });
        vm.prank(hop);
        remoteVaultHop.hopCompose(30255, bytes32(uint256(uint160(address(remoteVaultHop)))), oft, 10e18, abi.encode(message));

        assertEq(RemoteVaultDeposit(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2)).pricePerShare(), 885458600678000000, "Price per share should be updated");
        console.log("Price per share:", RemoteVaultDeposit(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2)).pricePerShare());

        balance = IERC20(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2)).balanceOf(address(this));
        console.log("Balance of deposit tokens:", balance);

        depositToken.redeem{value: fee}(balance);

        balance = IERC20(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2)).balanceOf(address(this));
        console.log("Balance of deposit tokens:", balance);

        message = RemoteVaultHop.RemoteVaultMessage({
            action: RemoteVaultHop.Action.RedeemReturn,
            userEid: 30184,
            userAddress: address(this),
            remoteEid: 30255,
            remoteVault: 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2,
            amount: 10E18,
            remoteTimestamp: 1759756962,
            pricePerShare: 885458600679000000
        });
        deal(frxUSD, address(remoteVaultHop), 10E18);
        vm.prank(hop);
        remoteVaultHop.hopCompose(30255, bytes32(uint256(uint160(address(remoteVaultHop)))), oft, 10e18, abi.encode(message));

        assertEq(RemoteVaultDeposit(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2)).pricePerShare(), 885458600678000000, "Price per share not yet updated");

        balance = IERC20(frxUSD).balanceOf(address(this));
        console.log("Balance of frxUSD:", balance);

        // forward 50 blocks
        vm.roll(block.number + 50);
        assertEq(RemoteVaultDeposit(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2)).pricePerShare(), 885458600678500000, "Price per share should be halfway updated");

        // forward another 60 blocks
        vm.roll(block.number + 60);
        assertEq(RemoteVaultDeposit(remoteVaultHop.depositToken(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2)).pricePerShare(), 885458600679000000, "Price per share should be fully updated");
    }


    function test_remote_hopCompose() public {
        setupFraxtal();
        vm.deal(address(remoteVaultHop), 1E18);

        RemoteVaultHop.RemoteVaultMessage memory message = RemoteVaultHop.RemoteVaultMessage({
            action: RemoteVaultHop.Action.Deposit,
            userEid: 30184,
            userAddress: address(this),
            remoteEid: 30255,
            remoteVault: 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2,
            amount: 10E18,
            remoteTimestamp: 0,
            pricePerShare: 0
        });

        deal(frxUSD, address(remoteVaultHop), 10E18);
        vm.prank(hop);
        remoteVaultHop.hopCompose(30255, bytes32(uint256(uint160(address(remoteVaultHop)))), oft, 10e18, abi.encode(message));

        uint256 vaultTokens = IERC20(0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2).balanceOf(address(remoteVaultHop));
        console.log("vaultTokens",vaultTokens);

        message = RemoteVaultHop.RemoteVaultMessage({
            action: RemoteVaultHop.Action.Redeem,
            userEid: 30184,
            userAddress: address(this),
            remoteEid: 30255,
            remoteVault: 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2,
            amount: vaultTokens,
            remoteTimestamp: 0,
            pricePerShare: 0
        });
        vm.prank(hop);
        remoteVaultHop.hopCompose(30255, bytes32(uint256(uint160(address(remoteVaultHop)))), oft, 0, abi.encode(message));


        vaultTokens = IERC20(0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2).balanceOf(address(remoteVaultHop));
        console.log("vaultTokens",vaultTokens);

    }
}