// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Test, console2 } from "forge-std/Test.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { FraxtalMintRedeemHop } from "src/contracts/hop/FraxtalMintRedeemHop.sol";

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
}

/// @dev Needs `--evm-version cancun`: the ERC4626 mint/redeemer uses transient storage.
/// @notice Measures the LIVE Fraxtal hub's `lzCompose` gas for the Tempo lane (srcEid 30410, five-DVN send
///         back) against the 1M compose budget every remote mint/redeem hop hard-codes in `_generateSendParam`.
///         If this stops fitting, composes from Tempo fail and must be retried by hand with more gas.
///         The hub does not know the Tempo hop yet, so `remoteHop[30410]` is set here by pranking the hub's
///         owner. Run with:
///
///         forge test --match-path src/test/hop/FraxtalMintRedeemHopTempoLaneTest.t.sol --evm-version cancun -vv
contract FraxtalMintRedeemHopTempoLaneTest is Test {
    uint32 internal constant TEMPO_EID = 30_410;
    uint128 internal constant COMPOSE_GAS = 1_000_000; // RemoteMintRedeemHop._generateSendParam
    /// @dev Endpoint-side overhead of `EndpointV2.lzCompose` (compose-queue check + clear) sits inside the same
    ///      budget, plus the 63/64 rule; leave room for both and for a fatter book on the day.
    uint256 internal constant MARGIN = 150_000;

    FraxtalMintRedeemHop internal constant HUB =
        FraxtalMintRedeemHop(payable(0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC));
    address internal constant FRAXTAL_MSIG = 0x5f25218ed9474b721d6a38c115107428E832fA2E;
    address internal constant FRXUSD = 0xFc00000000000000000000000000000000000001;
    address internal constant SFRXUSD = 0xfc00000000000000000000000000000000000008;

    address internal tempoHop;
    address internal recipient;

    function setUp() public {
        vm.createSelectFork(_rpc());
        tempoHop = makeAddr("tempoHop");
        recipient = makeAddr("recipient");
        vm.prank(HUB.owner());
        HUB.setRemoteHop(TEMPO_EID, tempoHop);
        assertFalse(HUB.paused(), "hub live");
        vm.deal(address(HUB), address(HUB).balance + 10 ether); // return-leg fee is paid in native FRAX
    }

    /// @dev frxUSD in from Tempo -> deposit -> sfrxUSD back to Tempo.
    function testFork_ComposeGas_DepositLane() public {
        uint256 amount = 10e18; // 10 frxUSD as credited by the Fraxtal lockbox (18 dp)
        deal(FRXUSD, address(HUB), amount);
        uint256 used = _compose(HUB.frxUsdLockbox(), 1, amount);
        console2.log("deposit lane lzCompose gas", used, "budget", COMPOSE_GAS);
        assertLt(used + MARGIN, COMPOSE_GAS, "deposit lane must fit the compose budget with margin");
    }

    /// @dev sfrxUSD in from Tempo -> redeem -> frxUSD back to Tempo.
    function testFork_ComposeGas_RedeemLane() public {
        uint256 amount = 10e18;
        deal(SFRXUSD, address(HUB), amount);
        uint256 used = _compose(HUB.sfrxUsdLockbox(), 2, amount);
        console2.log("redeem lane lzCompose gas", used, "budget", COMPOSE_GAS);
        assertLt(used + MARGIN, COMPOSE_GAS, "redeem lane must fit the compose budget with margin");
    }

    /// @dev Mirrors what the OFT and endpoint build: the hop's `abi.encode(recipient, EID)` compose payload,
    ///      prefixed with the sending hop's address by the OFT, wrapped by the endpoint with nonce/srcEid/amount.
    function _compose(address _oft, uint64 _nonce, uint256 _amountLD) internal returns (uint256 gasUsed) {
        bytes memory composeMsg = abi.encodePacked(
            bytes32(uint256(uint160(tempoHop))),
            abi.encode(bytes32(uint256(uint160(recipient))), TEMPO_EID)
        );
        bytes memory message = OFTComposeMsgCodec.encode(_nonce, TEMPO_EID, _amountLD, composeMsg);

        vm.prank(HUB.ENDPOINT());
        uint256 g = gasleft();
        HUB.lzCompose{ gas: COMPOSE_GAS }(_oft, bytes32(uint256(_nonce)), message, address(0), "");
        gasUsed = g - gasleft();
    }

    function _rpc() internal view returns (string memory rpcUrl) {
        rpcUrl = vm.envOr("FRAXTAL_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) rpcUrl = vm.envOr("FRAXTAL_MAINNET_URL", string(""));
        if (bytes(rpcUrl).length == 0) rpcUrl = "https://rpc.frax.com";
    }
}
