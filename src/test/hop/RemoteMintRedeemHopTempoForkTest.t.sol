// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Test } from "forge-std/Test.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { RemoteMintRedeemHopTempo } from "src/contracts/hop/RemoteMintRedeemHopTempo.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";
import { IOFT2 } from "src/contracts/hop/interfaces/IOFT2.sol";
import { TempoGasTokenBase } from "src/contracts/base/TempoGasTokenBase.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Exposes the base's fee collector so its zero-fee branch can be pinned without a full send.
contract CollectorHarness is TempoGasTokenBase {
    constructor(address _endpoint) TempoGasTokenBase(_endpoint) {}

    function collect(uint256 _fee, address _token) external returns (address) {
        return _collectNativeAltToken(_fee, _token, type(uint256).max);
    }
}

interface IEndpointV2AltLike {
    function nativeToken() external view returns (address);
}

interface ISendLibraryLike {
    function treasury() external view returns (address);
}

/// @notice Fork coverage for the Tempo variant of the mint/redeem hop that does not need Tempo's precompiles.
///
/// @dev Under stock foundry, Tempo's precompiles (TIP20s, FeeManager, StablecoinDEX) abort with
///      `EvmError: OpcodeNotFound`, so the tests that read them are guarded with `vm.skip`. Run with
///      `--network tempo` (forge >= 1.8) to execute those too; the fee-collection path itself is covered
///      end-to-end by `RemoteMintRedeemHopTempoE2E.t.sol`, which only runs under that flag.
contract RemoteMintRedeemHopTempoForkTest is Test {
    uint32 internal constant TEMPO_EID = 30_410;

    address internal constant TEMPO_ENDPOINT = 0x20Bb7C2E2f4e5ca2B4c57060d1aE2615245dCc9C;
    address internal constant EXECUTOR = 0xf851abCa1d0fD1Df8eAba6de466a102996b7d7B2;
    address internal constant DVN = 0x76FaFF60799021B301B45dC1BbEDE53F261F9961;
    address internal constant SEND_LIBRARY = 0x572863d9247E52026E0892d9Cd2E519B41EdB73C;

    address internal constant FRAXTAL_MINTREDEEM_HOP = 0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC;
    address internal constant FRXUSD_OFT = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
    address internal constant SFRXUSD_OFT = 0x00000000fD8C4B8A413A06821456801295921a71;
    address internal constant WFRAX_OFT = 0x00000000E9CE0f293D1Ce552768b187eBA8a56D4;

    address internal constant TEMPO_MSIG = 0x1Ba19a54a01AE967f5E3895764Caaa6919FD2bEe;
    uint256 internal constant NUM_DVNS = 5;

    RemoteMintRedeemHopTempo internal hop;
    address internal user;

    function setUp() public {
        vm.createSelectFork(_tempoRpcUrl());

        user = makeAddr("user");
        hop = new RemoteMintRedeemHopTempo({
            _owner: TEMPO_MSIG,
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_MINTREDEEM_HOP))),
            _numDVNs: NUM_DVNS,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: ISendLibraryLike(SEND_LIBRARY).treasury(),
            _EID: TEMPO_EID,
            _frxUsdOft: FRXUSD_OFT,
            _sfrxUsdOft: SFRXUSD_OFT,
            _endpoint: TEMPO_ENDPOINT
        });
    }

    /// @dev The whole reason this variant exists: fees ride on the endpoint's alt ERC20, not native.
    function testFork_BindsEndpointAltNativeToken() public view {
        assertEq(
            address(hop.nativeToken()),
            IEndpointV2AltLike(TEMPO_ENDPOINT).nativeToken(),
            "alt native token mismatch"
        );
        assertTrue(address(hop.nativeToken()) != address(0), "alt native token unset");
    }

    function testFork_StoresConstructorParams() public view {
        assertEq(hop.owner(), TEMPO_MSIG, "owner");
        assertEq(hop.fraxtalHop(), bytes32(uint256(uint160(FRAXTAL_MINTREDEEM_HOP))), "fraxtalHop");
        assertEq(hop.numDVNs(), NUM_DVNS, "numDVNs");
        assertEq(hop.EID(), TEMPO_EID, "EID");
        assertEq(hop.frxUsdOft(), FRXUSD_OFT, "frxUsdOft");
        assertEq(hop.sfrxUsdOft(), SFRXUSD_OFT, "sfrxUsdOft");
        assertEq(hop.EXECUTOR(), EXECUTOR, "EXECUTOR");
        assertEq(hop.DVN(), DVN, "DVN");
        assertEq(hop.TREASURY(), ISendLibraryLike(SEND_LIBRARY).treasury(), "TREASURY");
        assertEq(hop.version(), "1.0.1-tempo", "version");
        assertFalse(hop.paused(), "paused");
    }

    /// @dev Native gas sent here would be stranded -- the OFT is paid in TIP20, so reject it loudly.
    ///      Under Tempo's EVM (`--network tempo`) a value-carrying CALL already fails before the callee runs,
    ///      with empty revert data; under stock foundry the contract's own guard answers. Both are rejections.
    function testFork_MintRedeemRejectsMsgValue() public {
        _assertValueCallRejected(FRXUSD_OFT, 1e6);
    }

    /// @dev msg.value is rejected before anything else, so a bad OFT with value still reports the value error.
    function testFork_MsgValueCheckPrecedesOftCheck() public {
        _assertValueCallRejected(WFRAX_OFT, 1e18);
    }

    function _assertValueCallRejected(address _oft, uint256 _amount) internal {
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool ok, bytes memory data) = address(hop).call{ value: 1 wei }(
            abi.encodeCall(RemoteMintRedeemHop.mintRedeem, (_oft, _amount))
        );
        assertFalse(ok, "value call must be rejected");
        if (data.length > 0) {
            assertEq(
                data,
                abi.encodeWithSelector(TempoGasTokenBase.OFTAltCore__msg_value_not_zero.selector, 1 wei),
                "when the contract's guard runs it must report the value error"
            );
        }
    }

    /// @dev Deploying against an endpoint that is not an EndpointV2Alt fails at construction, not on first use.
    function testFork_ConstructorRejectsNonAltEndpoint() public {
        address treasury = ISendLibraryLike(SEND_LIBRARY).treasury(); // resolve before expectRevert
        vm.mockCall(TEMPO_ENDPOINT, abi.encodeWithSignature("nativeToken()"), abi.encode(address(0)));
        vm.expectRevert(TempoGasTokenBase.NativeTokenUnavailable.selector);
        new RemoteMintRedeemHopTempo({
            _owner: TEMPO_MSIG,
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_MINTREDEEM_HOP))),
            _numDVNs: NUM_DVNS,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: treasury,
            _EID: TEMPO_EID,
            _frxUsdOft: FRXUSD_OFT,
            _sfrxUsdOft: SFRXUSD_OFT,
            _endpoint: TEMPO_ENDPOINT
        });
        vm.clearMockedCalls();
    }

    /// @dev A zero fee collects nothing and must say so: returning the caller's raw token here would let the
    ///      hop bind and approve a token it never received.
    function testFork_ZeroFeeCollectsNothing() public {
        CollectorHarness collector = new CollectorHarness(TEMPO_ENDPOINT);
        assertEq(collector.collect(0, address(0xBEEF)), address(0), "zero fee -> no payment token");
    }

    /// @dev DEX-routed fee swaps carry a slippage allowance (the DEX quotes per tick but settles per order,
    ///      so a fill can need more input than quoted). Default 50 bps, owner-tunable up to 200, 0 restores
    ///      the default. The swap itself is covered by the E2E suite under `--network tempo`.
    function testFork_FeeSwapSlippageBpsDefaultAndBounds() public {
        assertEq(hop.feeSwapSlippageBps(), 50, "default headroom");

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        hop.setFeeSwapSlippageBps(100);

        vm.prank(TEMPO_MSIG);
        vm.expectRevert(abi.encodeWithSelector(TempoGasTokenBase.FeeSwapSlippageTooHigh.selector, uint16(201)));
        hop.setFeeSwapSlippageBps(201);

        vm.prank(TEMPO_MSIG);
        vm.expectEmit(true, true, true, true, address(hop));
        emit TempoGasTokenBase.FeeSwapSlippageBpsSet(200);
        hop.setFeeSwapSlippageBps(200);
        assertEq(hop.feeSwapSlippageBps(), 200, "max accepted");

        vm.prank(TEMPO_MSIG);
        hop.setFeeSwapSlippageBps(0);
        assertEq(hop.feeSwapSlippageBps(), 50, "0 restores the default");
    }

    /// @dev The capped overload needs an explicit fee token; zero is rejected before any precompile is touched.
    function testFork_MintRedeemRejectsZeroFeeToken() public {
        vm.prank(user);
        vm.expectRevert(RemoteMintRedeemHopTempo.InvalidFeeToken.selector);
        hop.mintRedeem(FRXUSD_OFT, 1e6, address(0), type(uint256).max);
    }

    /// @dev Recovery is owner-only; the native sweep is dead on Tempo and says so rather than silently no-op.
    function testFork_RecoveryIsOwnerOnlyAndNativeIsNotImplemented() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        hop.recoverERC20(address(0xBEEF), user, 1);

        vm.prank(TEMPO_MSIG);
        vm.expectRevert(RemoteMintRedeemHopTempo.NotImplemented.selector);
        hop.recoverETH(TEMPO_MSIG, 1);
    }

    function testFork_MintRedeemRejectsUnapprovedOft() public {
        vm.prank(user);
        vm.expectRevert(RemoteMintRedeemHop.InvalidOFT.selector);
        hop.mintRedeem(WFRAX_OFT, 1e18);
    }

    function testFork_MintRedeemRespectsPause() public {
        vm.prank(TEMPO_MSIG);
        hop.pause(true);

        vm.prank(user);
        vm.expectRevert(RemoteMintRedeemHop.HopPaused.selector);
        hop.mintRedeem(FRXUSD_OFT, 1e6);
    }

    /// @dev frxUSD on Tempo is a 6-decimal TIP20 adapter with decimalConversionRate 1, so removeDust is
    ///      the identity and no amount can round to zero. sfrxUSD is a normal 18-decimal OFT (rate 1e12),
    ///      where sub-dust amounts must be rejected rather than silently bridging nothing.
    function testFork_MintRedeemRejectsDustOnlyAmount() public {
        _skipUnlessOftCallable();

        vm.prank(user);
        vm.expectRevert(RemoteMintRedeemHop.ZeroAmountSend.selector);
        hop.mintRedeem(SFRXUSD_OFT, 1e11);
    }

    /// @dev Fees are denominated in LZD (6 decimals), so a sane quote is dollars-and-cents sized, not
    ///      ether-sized. This would catch a units regression from copying the native-chain contract.
    function testFork_QuoteIsDenominatedInAltToken() public {
        _skipUnlessTip20Callable();

        bytes32 to = bytes32(uint256(uint160(user)));

        MessagingFee memory frxUsdFee = hop.quote(FRXUSD_OFT, to, 1e6);
        MessagingFee memory sfrxUsdFee = hop.quote(SFRXUSD_OFT, to, 1e18);

        assertGt(frxUsdFee.nativeFee, 0, "frxUSD fee zero");
        assertGt(sfrxUsdFee.nativeFee, 0, "sfrxUSD fee zero");
        assertEq(frxUsdFee.lzTokenFee, 0, "lzTokenFee should be unused");

        // 6-decimal stablecoin units: a hop costing more than $100 means the quote is in the wrong units.
        assertLt(frxUsdFee.nativeFee, 100e6, "frxUSD fee implausible for LZD units");
        assertLt(sfrxUsdFee.nativeFee, 100e6, "sfrxUSD fee implausible for LZD units");
    }

    /// @dev The quote must be the outbound message fee plus the retained return-leg estimate; if the
    ///      hop portion were dropped, the contract would under-collect and strand Fraxtal's send back.
    function testFork_QuoteIsSendFeePlusHopFee() public {
        _skipUnlessTip20Callable();

        bytes32 to = bytes32(uint256(uint160(user)));
        MessagingFee memory quoted = hop.quote(FRXUSD_OFT, to, 1e6);
        assertEq(quoted.nativeFee - hop.quoteHop(), _rawOftSendFee(FRXUSD_OFT, to, 1e6), "fee composition");
        assertGt(hop.quoteHop(), 0, "hop fee zero");
    }

    /// @dev A token the endpoint already whitelists needs no DEX swap, so the user-token quote is the
    ///      endpoint fee 1:1. This is the one `_quoteUserTokenFee` branch reachable without precompiles.
    function testFork_UserTokenQuoteIsIdentityForWhitelistedToken() public {
        _skipUnlessTip20Callable();

        address[] memory whitelisted = hop.nativeToken().getWhitelistedTokens();
        assertGt(whitelisted.length, 0, "no whitelisted tokens on fork");

        bytes32 to = bytes32(uint256(uint160(user)));
        uint256 endpointFee = hop.quote(FRXUSD_OFT, to, 1e6).nativeFee;

        assertEq(
            hop.quoteUserTokenFee(FRXUSD_OFT, to, 1e6, whitelisted[0]),
            endpointFee,
            "whitelisted token should quote 1:1"
        );
    }

    /// @dev The mesh OFT proxies contain PUSH0, so under the repo default `paris` any call into them
    ///      aborts with `EvmError: NotActivated`. Pass `--evm-version shanghai` for real coverage.
    function _skipUnlessOftCallable() internal {
        try IOFT2(FRXUSD_OFT).decimalConversionRate() returns (uint256) {
            return;
        } catch {
            vm.skip(true);
        }
    }

    /// @dev Tempo's protocol-native accounts (TIP20s, the fee manager, the stablecoin DEX) are not
    ///      executable inside stock foundry's fork EVM -- calls into them abort with
    ///      `EvmError: OpcodeNotFound`. The quote paths read the frxUSD TIP20, so probe and skip rather
    ///      than report red for a toolchain gap. Run under Tempo-patched foundry for real coverage; the
    ///      values these assert were confirmed by hand against mainnet (quoteSend 260466 LZD, 6dp).
    function _skipUnlessTip20Callable() internal {
        _skipUnlessOftCallable();
        try IERC20Metadata(IOFT(FRXUSD_OFT).token()).decimals() returns (uint8) {
            return;
        } catch {
            vm.skip(true);
        }
    }

    /// @dev Mirror of the contract's own send params, so a drift on either side shows up as a mismatch.
    function _rawOftSendFee(address _oft, bytes32 _to, uint256 _amountLD) internal view returns (uint256) {
        SendParam memory sendParam;
        sendParam.dstEid = 30_255;
        sendParam.to = hop.fraxtalHop();
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _amountLD;
        sendParam.extraOptions = hex"0003010013030000000000000000000000000000000f4240";
        sendParam.composeMsg = abi.encode(_to, TEMPO_EID);

        return IOFT(_oft).quoteSend(sendParam, false).nativeFee;
    }

    function _tempoRpcUrl() internal view returns (string memory rpcUrl) {
        rpcUrl = vm.envOr("TEMPO_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) rpcUrl = vm.envOr("TEMPO_MAINNET_URL", string(""));
        if (bytes(rpcUrl).length == 0) rpcUrl = "https://rpc.tempo.xyz";
    }
}
