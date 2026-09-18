// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Test, console2 } from "forge-std/Test.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { IStablecoinDEX } from "tempo-std/interfaces/IStablecoinDEX.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";
import { RemoteMintRedeemHopTempo } from "src/contracts/hop/RemoteMintRedeemHopTempo.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";
import { TempoGasTokenBase } from "src/contracts/base/TempoGasTokenBase.sol";
import { ILZEndpointDollar } from "src/contracts/interfaces/vendor/layerzero/ILZEndpointDollar.sol";

interface ISendLibraryLike {
    function treasury() external view returns (address);
}

interface IEndpointLike {
    function outboundNonce(address _sender, uint32 _dstEid, bytes32 _receiver) external view returns (uint64);
}

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

/// @dev Integrator-style caller: a contract that never called setUserToken, so the hop must fall back to pathUSD.
contract IntegratorCaller {
    function go(RemoteMintRedeemHopTempo hop, address oft, uint256 amountLD, address feeToken, uint256 fee) external {
        IERC20Like(IOFT(oft).token()).approve(address(hop), amountLD);
        IERC20Like(feeToken).approve(address(hop), fee);
        hop.mintRedeem(oft, amountLD);
    }
}

/// @notice End-to-end coverage of RemoteMintRedeemHopTempo against LIVE Tempo bytecode (OFTs, EndpointV2Alt,
///         LZEndpointDollar, FeeManager, StablecoinDEX). Tempo's precompiles are only executable under
///         `--network tempo`, so this suite is not run by the stock `forge test`:
///
///         forge test --match-path src/test/hop/RemoteMintRedeemHopTempoE2E.t.sol --network tempo --evm-version shanghai -vv
///
/// @dev This suite is CI's canary for Tempo precompile behaviour the hop relies on but that no Solidity spec
///      documents any more (the reference spec was removed upstream at tempo v1.1.0; the source of truth is
///      tempoxyz/tempo `crates/precompiles/src/`): a contract may `setUserToken` for itself
///      (`testFork_E2E_FeeTokenRebindingAcrossUsers`), the DEX may settle for more than it quoted
///      (`testFork_E2E_FrxUsdFeeViaDex_SurvivesQuoteFillDivergence`), and the LZD whitelist decides the fee path.
contract RemoteMintRedeemHopTempoE2EForkTest is Test {
    uint32 internal constant TEMPO_EID = 30_410;
    uint32 internal constant FRAXTAL_EID = 30_255;
    address internal constant TEMPO_ENDPOINT = 0x20Bb7C2E2f4e5ca2B4c57060d1aE2615245dCc9C;
    address internal constant EXECUTOR = 0xf851abCa1d0fD1Df8eAba6de466a102996b7d7B2;
    address internal constant DVN = 0x76FaFF60799021B301B45dC1BbEDE53F261F9961;
    address internal constant SEND_LIBRARY = 0x572863d9247E52026E0892d9Cd2E519B41EdB73C;
    address internal constant FRAXTAL_MINTREDEEM_HOP = 0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC;
    address internal constant FRXUSD_OFT = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
    address internal constant SFRXUSD_OFT = 0x00000000fD8C4B8A413A06821456801295921a71;
    address internal constant TEMPO_MSIG = 0x1Ba19a54a01AE967f5E3895764Caaa6919FD2bEe;
    address internal constant USDC_E = 0x20C000000000000000000000b9537d11c60E8b50;
    address internal constant PATH_USD = StdTokens.PATH_USD_ADDRESS;
    address internal constant DEX = StdPrecompiles.STABLECOIN_DEX_ADDRESS;

    /// @dev Mirror of TempoGasTokenBase.DEFAULT_FEE_SWAP_SLIPPAGE_BPS.
    uint256 internal constant DEFAULT_FEE_SWAP_SLIPPAGE_BPS = 50;
    /// @dev StablecoinDEX.MIN_ORDER_AMOUNT: the smallest resting order a maker can place.
    uint128 internal constant MIN_ORDER = 1e8;

    RemoteMintRedeemHopTempo internal hop;
    ILZEndpointDollar internal lzd;
    address internal frxUsd;
    address internal user;
    bytes32 internal to;

    event MintRedeem(address oft, address indexed sender, uint256 amountLD);
    event FeeCollected(address indexed paymentToken, uint256 sendFee, uint256 retained);
    event RecoveredERC20(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public {
        vm.createSelectFork(_rpc());
        user = makeAddr("user");
        to = bytes32(uint256(uint160(user)));

        hop = new RemoteMintRedeemHopTempo({
            _owner: TEMPO_MSIG,
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_MINTREDEEM_HOP))),
            _numDVNs: 5,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: ISendLibraryLike(SEND_LIBRARY).treasury(),
            _EID: TEMPO_EID,
            _frxUsdOft: FRXUSD_OFT,
            _sfrxUsdOft: SFRXUSD_OFT,
            _endpoint: TEMPO_ENDPOINT
        });
        frxUsd = IOFT(FRXUSD_OFT).token();
        lzd = hop.nativeToken();

        // Fund the user: mint frxUSD through the adapter's ISSUER_ROLE, then buy pathUSD on the real DEX.
        vm.prank(FRXUSD_OFT);
        ITIP20(frxUsd).mint(user, 1_000e6);
        vm.startPrank(user);
        ITIP20(frxUsd).approve(DEX, 100e6);
        StdPrecompiles.STABLECOIN_DEX.swapExactAmountOut(frxUsd, PATH_USD, 5e6, 6e6);
        vm.stopPrank();
        assertGe(_bal(PATH_USD, user), 5e6, "setup: user has pathUSD");
    }

    // ───────────────────────── happy paths ─────────────────────────

    function testFork_E2E_FrxUsd_PathUsdFee() public {
        uint256 amount = 10e6;
        MessagingFee memory q = hop.quote(FRXUSD_OFT, to, amount);
        uint256 hopFee = hop.quoteHop();
        uint256 feeInPath = hop.quoteUserTokenFee(FRXUSD_OFT, to, amount, PATH_USD);
        assertEq(feeInPath, q.nativeFee, "whitelisted token quotes 1:1");
        assertGt(hopFee, 0, "hop fee");
        console2.log("quote.nativeFee (LZD 6dp)", q.nativeFee, "quoteHop", hopFee);

        uint256 uFrx0 = _bal(frxUsd, user);
        uint256 uPath0 = _bal(PATH_USD, user);
        uint256 hopPath0 = _bal(PATH_USD, address(hop));
        uint256 frxSupply0 = IERC20Like(frxUsd).totalSupply();
        uint256 lzdSupply0 = IERC20Like(address(lzd)).totalSupply();
        uint64 nonce0 = IEndpointLike(TEMPO_ENDPOINT).outboundNonce(FRXUSD_OFT, FRAXTAL_EID, _peer(FRXUSD_OFT));

        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount);
        ITIP20(PATH_USD).approve(address(hop), feeInPath);
        vm.expectEmit(true, true, true, true, address(hop));
        emit FeeCollected(PATH_USD, q.nativeFee - hopFee, hopFee);
        vm.expectEmit(true, true, true, true, address(hop));
        emit MintRedeem(FRXUSD_OFT, user, amount);
        hop.mintRedeem(FRXUSD_OFT, amount);
        vm.stopPrank();

        assertEq(uFrx0 - _bal(frxUsd, user), amount, "user debited bridged amount");
        assertEq(uPath0 - _bal(PATH_USD, user), q.nativeFee, "user debited exactly the quoted fee");
        assertEq(_bal(PATH_USD, address(hop)) - hopPath0, hopFee, "hop retains quoteHop()");
        assertEq(_bal(frxUsd, address(hop)), 0, "no frxUSD stranded on hop");
        assertEq(frxSupply0 - IERC20Like(frxUsd).totalSupply(), amount, "adapter burned the bridged amount");
        assertEq(
            IERC20Like(address(lzd)).totalSupply() - lzdSupply0,
            q.nativeFee - hopFee,
            "send fee wrapped into LZD"
        );
        assertEq(
            IEndpointLike(TEMPO_ENDPOINT).outboundNonce(FRXUSD_OFT, FRAXTAL_EID, _peer(FRXUSD_OFT)) - nonce0,
            1,
            "one packet sent to Fraxtal"
        );
        assertEq(IERC20Like(frxUsd).allowance(address(hop), FRXUSD_OFT), 0, "no residual frxUSD allowance to OFT");
        assertEq(IERC20Like(PATH_USD).allowance(address(hop), FRXUSD_OFT), 0, "no residual fee allowance to OFT");
        assertEq(IERC20Like(frxUsd).allowance(user, address(hop)), 0, "user frxUSD allowance fully consumed");
        assertEq(IERC20Like(PATH_USD).allowance(user, address(hop)), 0, "user pathUSD allowance fully consumed");
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), PATH_USD, "hop bound to payment token");
    }

    /// @dev frxUSD is not LZD-whitelisted, so the fee is swapped on the DEX. The hop pulls the quote plus the
    ///      slippage allowance, settles, and refunds whatever the swap did not consume.
    function testFork_E2E_FrxUsd_FrxUsdFeeViaDex() public {
        vm.prank(user, user);
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(frxUsd);
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(user), frxUsd, "user fee token = frxUSD");

        uint256 amount = 10e6;
        MessagingFee memory q = hop.quote(FRXUSD_OFT, to, amount);
        uint256 hopFee = hop.quoteHop();
        (address expectedTarget, uint128 rawQuote) = _rawSwapQuote(frxUsd, uint128(q.nativeFee));
        uint256 feeInFrx = hop.quoteUserTokenFee(FRXUSD_OFT, to, amount, frxUsd);
        assertEq(feeInFrx, _padded(rawQuote), "DEX-routed quote = raw DEX quote + default headroom");
        console2.log("fee in LZD units", q.nativeFee, "raw DEX quote", rawQuote);
        console2.log("padded quote in frxUSD", feeInFrx);

        address[] memory wl = lzd.getWhitelistedTokens();
        uint256[] memory hopWl0 = new uint256[](wl.length);
        for (uint256 i; i < wl.length; ++i) hopWl0[i] = _bal(wl[i], address(hop));
        uint256 uFrx0 = _bal(frxUsd, user);
        uint256 uPath0 = _bal(PATH_USD, user);
        uint256 lzdSupply0 = IERC20Like(address(lzd)).totalSupply();

        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount + feeInFrx);
        hop.mintRedeem(FRXUSD_OFT, amount);
        vm.stopPrank();

        uint256 spent = uFrx0 - _bal(frxUsd, user) - amount;
        console2.log("frxUSD settled", spent, "refunded", feeInFrx - spent);
        assertGe(spent, rawQuote, "settled for at least the raw quote");
        assertLe(spent, feeInFrx, "net debit within the padded quote");
        assertEq(_bal(frxUsd, address(hop)), 0, "unspent headroom refunded, no frxUSD stranded on hop");
        assertEq(IERC20Like(frxUsd).allowance(address(hop), DEX), 0, "hop->DEX allowance cleared");
        assertEq(IERC20Like(frxUsd).allowance(user, address(hop)), 0, "user allowance fully consumed");
        assertEq(_bal(PATH_USD, user), uPath0, "user pathUSD untouched");
        assertEq(
            IERC20Like(address(lzd)).totalSupply() - lzdSupply0,
            q.nativeFee - hopFee,
            "send fee wrapped into LZD"
        );

        // The router picks the CHEAPEST whitelisted target, which need not be pathUSD; the hop retains the
        // return-leg estimate in whichever token it bought and binds its FeeManager token to it.
        address paid = StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop));
        assertEq(paid, expectedTarget, "hop bound to the cheapest whitelisted target");
        console2.log("payment token chosen by _findSwapTarget", paid);
        for (uint256 i; i < wl.length; ++i) {
            uint256 delta = _bal(wl[i], address(hop)) - hopWl0[i];
            if (wl[i] == paid) {
                assertEq(delta, hopFee, "hop retains quoteHop() in the payment token");
            } else {
                assertEq(delta, 0, "other whitelisted tokens untouched");
            }
        }
    }

    /// @dev Regression for the zero-headroom swap (M-1 in the 2026-09-16 review). The DEX quotes exact-out
    ///      swaps per tick but settles per order, rounding each order's input up, so a fill that crosses an
    ///      order boundary can need more input than quoted. The hop used to swap with `maxAmountIn == quote`
    ///      and revert `MaxInputExceeded` on such books -- griefable, since anyone can shape the book.
    ///      Build such a book for the hop's actual fee size, prove the un-padded swap fails on it, then prove
    ///      `mintRedeem` succeeds and refunds the unspent headroom.
    function testFork_E2E_FrxUsdFeeViaDex_SurvivesQuoteFillDivergence() public {
        vm.prank(user, user);
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(frxUsd);

        uint256 amount = 10e6;
        uint128 needOut = uint128(hop.quote(FRXUSD_OFT, to, amount).nativeFee);

        (address maker, address sweeper) = _fundBookShapers();
        (bool found, address target, uint128 rawQuote) = _shapeDivergentBook(maker, sweeper, needOut);
        if (!found) {
            console2.log("could not build a divergent book for this fee size; skipping");
            vm.skip(true);
        }

        uint256 feeInFrx = hop.quoteUserTokenFee(FRXUSD_OFT, to, amount, frxUsd);
        assertEq(feeInFrx, _padded(rawQuote), "padded quote carries headroom");

        uint256 uFrx0 = _bal(frxUsd, user);
        uint256 hopTarget0 = _bal(target, address(hop));
        uint256 hopFee = hop.quoteHop();

        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount + feeInFrx);
        hop.mintRedeem(FRXUSD_OFT, amount); // reverted MaxInputExceeded before the fix
        vm.stopPrank();

        uint256 spent = uFrx0 - _bal(frxUsd, user) - amount;
        console2.log("raw quote", rawQuote, "settled", spent);
        assertGt(spent, rawQuote, "settlement needed more input than the per-tick quote");
        assertLe(spent, feeInFrx, "net debit within the padded quote");
        assertEq(_bal(frxUsd, address(hop)), 0, "unspent headroom refunded, no frxUSD stranded on hop");
        assertEq(IERC20Like(frxUsd).allowance(address(hop), DEX), 0, "hop->DEX allowance cleared");
        assertEq(IERC20Like(frxUsd).allowance(user, address(hop)), 0, "user allowance fully consumed");
        assertEq(_bal(target, address(hop)) - hopTarget0, hopFee, "hop retains quoteHop() in the payment token");
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), target, "hop bound to the payment token");
    }

    function testFork_E2E_SfrxUsd_PathUsdFee() public {
        uint256 amount = 1e18;
        deal(SFRXUSD_OFT, user, amount);
        MessagingFee memory q = hop.quote(SFRXUSD_OFT, to, amount);
        uint256 hopFee = hop.quoteHop();
        uint256 s0 = _bal(SFRXUSD_OFT, user);
        uint256 supply0 = IERC20Like(SFRXUSD_OFT).totalSupply();
        uint256 uPath0 = _bal(PATH_USD, user);
        uint256 hopPath0 = _bal(PATH_USD, address(hop));
        uint64 nonce0 = IEndpointLike(TEMPO_ENDPOINT).outboundNonce(SFRXUSD_OFT, FRAXTAL_EID, _peer(SFRXUSD_OFT));

        vm.startPrank(user);
        IERC20Like(SFRXUSD_OFT).approve(address(hop), amount);
        ITIP20(PATH_USD).approve(address(hop), q.nativeFee);
        hop.mintRedeem(SFRXUSD_OFT, amount);
        vm.stopPrank();

        assertEq(s0 - _bal(SFRXUSD_OFT, user), amount, "user debited sfrxUSD");
        assertEq(supply0 - IERC20Like(SFRXUSD_OFT).totalSupply(), amount, "OFT burned sfrxUSD");
        assertEq(uPath0 - _bal(PATH_USD, user), q.nativeFee, "user debited exactly the quoted fee");
        assertEq(_bal(PATH_USD, address(hop)) - hopPath0, hopFee, "hop retains quoteHop()");
        assertEq(_bal(SFRXUSD_OFT, address(hop)), 0, "no sfrxUSD stranded on hop");
        assertEq(
            IEndpointLike(TEMPO_ENDPOINT).outboundNonce(SFRXUSD_OFT, FRAXTAL_EID, _peer(SFRXUSD_OFT)) - nonce0,
            1,
            "one packet sent"
        );
        // A mintable OFT burns from the caller, so the hop must not leave a dead self-allowance behind.
        assertFalse(IOFT(SFRXUSD_OFT).approvalRequired(), "sfrxUSD OFT burns without allowance");
        assertEq(IERC20Like(SFRXUSD_OFT).allowance(address(hop), SFRXUSD_OFT), 0, "no residual sfrxUSD allowance");
    }

    /// @dev Two users with different whitelisted fee tokens back-to-back: the hop must re-bind its FeeManager token
    ///      each call so the OFT pulls the token the hop actually collected.
    function testFork_E2E_FeeTokenRebindingAcrossUsers() public {
        address userB = makeAddr("userB");
        vm.prank(FRXUSD_OFT);
        ITIP20(frxUsd).mint(userB, 100e6);
        // Get USDC.e for userB via the DEX (multi-hop through pathUSD); skip if no route/liquidity.
        vm.startPrank(userB);
        ITIP20(frxUsd).approve(DEX, 50e6);
        (bool ok, ) = DEX.call(
            abi.encodeCall(IStablecoinDEX.swapExactAmountOut, (frxUsd, USDC_E, uint128(2e6), uint128(3e6)))
        );
        vm.stopPrank();
        if (!ok) {
            console2.log("no frxUSD->USDC.e route on this fork; skipping rebinding test");
            vm.skip(true);
        }
        vm.prank(userB, userB);
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(USDC_E);

        uint256 amount = 5e6;
        bytes32 toB = bytes32(uint256(uint160(userB)));
        MessagingFee memory qB = hop.quote(FRXUSD_OFT, toB, amount);
        uint256 hopFee = hop.quoteHop();
        uint256 hopUsdc0 = _bal(USDC_E, address(hop));

        vm.startPrank(userB);
        ITIP20(frxUsd).approve(address(hop), amount);
        ITIP20(USDC_E).approve(address(hop), qB.nativeFee);
        hop.mintRedeem(FRXUSD_OFT, amount);
        vm.stopPrank();
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), USDC_E, "hop bound to USDC.e");
        assertEq(_bal(USDC_E, address(hop)) - hopUsdc0, hopFee, "hop retains hop fee in USDC.e");

        // Now the default-token user: binding must flip back to pathUSD.
        MessagingFee memory qA = hop.quote(FRXUSD_OFT, to, amount);
        uint256 hopPath0 = _bal(PATH_USD, address(hop));
        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount);
        ITIP20(PATH_USD).approve(address(hop), qA.nativeFee);
        hop.mintRedeem(FRXUSD_OFT, amount);
        vm.stopPrank();
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), PATH_USD, "hop re-bound to pathUSD");
        assertEq(_bal(PATH_USD, address(hop)) - hopPath0, hop.quoteHop(), "hop retains hop fee in pathUSD");
    }

    /// @dev Regression for the stale-binding ordering (L-1 in the 2026-09-16 review). The OFT's quote validates
    ///      THIS contract's FeeManager binding, which used to be whatever the previous caller paid with. Had that
    ///      token later left the LZD whitelist with no DEX route out of it, every quote -- and so every
    ///      mintRedeem -- would have reverted before the re-bind could run, with no way back. The hop now
    ///      re-binds to the current caller's token and quotes again when the OFT rejects the inherited binding,
    ///      so it can never block the next call.
    function testFork_E2E_InheritedBindingCannotBlockNextCaller() public {
        uint256 amount = 10e6;

        // A previous USDC.e payer left the hop bound to USDC.e (only the hop can write its own slot).
        vm.prank(address(hop));
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(USDC_E);
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), USDC_E, "hop inherits USDC.e binding");

        // LayerZero then delists USDC.e, and the DEX has no route out of it.
        vm.mockCall(address(lzd), abi.encodeCall(ILZEndpointDollar.isWhitelistedToken, (USDC_E)), abi.encode(false));
        vm.mockCallRevert(
            DEX,
            abi.encodeWithSelector(IStablecoinDEX.quoteSwapExactAmountOut.selector, USDC_E),
            abi.encodeWithSelector(IStablecoinDEX.InsufficientLiquidity.selector)
        );

        // The inherited binding now poisons the OFT's quote, which is what the hop's own view runs.
        vm.expectRevert(abi.encodeWithSelector(TempoGasTokenBase.NoSwappableWhitelistedToken.selector, USDC_E));
        hop.quote(FRXUSD_OFT, to, amount);

        // A pathUSD payer still gets through: the hop binds pathUSD before it quotes.
        uint256 hopFee = hop.quoteHop();
        uint256 uPath0 = _bal(PATH_USD, user);
        uint256 hopPath0 = _bal(PATH_USD, address(hop));
        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount);
        ITIP20(PATH_USD).approve(address(hop), 5e6);
        hop.mintRedeem(FRXUSD_OFT, amount); // reverted NoSwappableWhitelistedToken(USDC.e) without the retry
        vm.stopPrank();

        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), PATH_USD, "hop re-bound to pathUSD");
        assertGt(uPath0 - _bal(PATH_USD, user), hopFee, "fee paid in pathUSD");
        assertEq(_bal(PATH_USD, address(hop)) - hopPath0, hopFee, "hop retains quoteHop() in pathUSD");
        assertEq(_bal(frxUsd, address(hop)), 0, "no frxUSD stranded on hop");

        // The successful call healed the view for everyone else, too.
        MessagingFee memory q = hop.quote(FRXUSD_OFT, to, amount);
        assertGt(q.nativeFee, 0, "quote healthy again");
        vm.clearMockedCalls();
    }

    // ───────────────────────── capped, token-explicit overload ─────────────────────────

    /// @dev The four-argument mintRedeem restores the fee ceiling that msg.value gives the native hop (L-2 in
    ///      the 2026-09-16 review): a cap below the live fee reverts before anything is pulled, a cap at the
    ///      live fee goes through, and the debit never exceeds it.
    function testFork_E2E_FeeCap_WhitelistedToken() public {
        uint256 amount = 10e6;
        uint256 fee = hop.quoteUserTokenFee(FRXUSD_OFT, to, amount, PATH_USD);
        uint256 uFrx0 = _bal(frxUsd, user);
        uint256 uPath0 = _bal(PATH_USD, user);

        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount);
        ITIP20(PATH_USD).approve(address(hop), fee);

        vm.expectRevert(abi.encodeWithSelector(TempoGasTokenBase.FeeAboveCap.selector, fee, fee - 1));
        hop.mintRedeem(FRXUSD_OFT, amount, PATH_USD, fee - 1);
        assertEq(_bal(frxUsd, user), uFrx0, "revert is atomic: principal not pulled");
        assertEq(_bal(PATH_USD, user), uPath0, "revert is atomic: fee not pulled");

        hop.mintRedeem(FRXUSD_OFT, amount, PATH_USD, fee);
        vm.stopPrank();

        assertEq(uFrx0 - _bal(frxUsd, user), amount, "principal debited");
        assertEq(uPath0 - _bal(PATH_USD, user), fee, "fee debited exactly at the cap");
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), PATH_USD, "hop bound to pathUSD");
    }

    /// @dev Same cap semantics on the DEX path: the cap is checked against the padded figure quoteUserTokenFee
    ///      reports, before the pull. The explicit token also overrides the caller's FeeManager binding.
    function testFork_E2E_FeeCap_DexRoutedToken() public {
        assertEq(hop.feeTokenOf(user), PATH_USD, "user is bound to pathUSD (default)");

        uint256 amount = 10e6;
        uint256 needOut = hop.quote(FRXUSD_OFT, to, amount).nativeFee;
        (address target, uint128 rawQuote) = _rawSwapQuote(frxUsd, uint128(needOut));
        uint256 feeInFrx = hop.quoteUserTokenFee(FRXUSD_OFT, to, amount, frxUsd);
        uint256 uFrx0 = _bal(frxUsd, user);
        uint256 uPath0 = _bal(PATH_USD, user);
        uint256 hopTarget0 = _bal(target, address(hop));

        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount + feeInFrx);

        vm.expectRevert(abi.encodeWithSelector(TempoGasTokenBase.FeeAboveCap.selector, feeInFrx, feeInFrx - 1));
        hop.mintRedeem(FRXUSD_OFT, amount, frxUsd, feeInFrx - 1);
        assertEq(_bal(frxUsd, user), uFrx0, "revert is atomic: nothing pulled");

        hop.mintRedeem(FRXUSD_OFT, amount, frxUsd, feeInFrx);
        vm.stopPrank();

        uint256 spent = uFrx0 - _bal(frxUsd, user) - amount;
        assertGe(spent, rawQuote, "settled for at least the raw quote");
        assertLe(spent, feeInFrx, "net fee debit within the cap");
        assertEq(_bal(PATH_USD, user), uPath0, "binding (pathUSD) ignored in favour of the explicit token");
        assertEq(_bal(frxUsd, address(hop)), 0, "unspent headroom refunded");
        assertEq(_bal(target, address(hop)) - hopTarget0, hop.quoteHop(), "hop retains quoteHop() in the swap target");
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), target, "hop bound to the swap target");
    }

    /// @dev L-4 mitigation: a caller whose FeeManager token is frxUSD (DEX-routed, thin book) can name a
    ///      whitelisted token and skip the DEX entirely.
    function testFork_E2E_ExplicitWhitelistedTokenBypassesDex() public {
        vm.prank(user, user);
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(frxUsd);
        assertEq(hop.feeTokenOf(user), frxUsd, "user is bound to frxUSD");

        uint256 amount = 10e6;
        uint256 fee = hop.quoteUserTokenFee(FRXUSD_OFT, to, amount, PATH_USD);
        uint256 uFrx0 = _bal(frxUsd, user);
        uint256 uPath0 = _bal(PATH_USD, user);
        uint256 hopPath0 = _bal(PATH_USD, address(hop));

        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount);
        ITIP20(PATH_USD).approve(address(hop), fee);
        hop.mintRedeem(FRXUSD_OFT, amount, PATH_USD, fee);
        vm.stopPrank();

        assertEq(uFrx0 - _bal(frxUsd, user), amount, "frxUSD debited for the principal only");
        assertEq(uPath0 - _bal(PATH_USD, user), fee, "fee paid 1:1 in pathUSD");
        assertEq(_bal(PATH_USD, address(hop)) - hopPath0, hop.quoteHop(), "hop retains quoteHop() in pathUSD");
        assertEq(IERC20Like(frxUsd).allowance(address(hop), DEX), 0, "DEX never involved");
        assertEq(StdPrecompiles.TIP_FEE_MANAGER.userTokens(address(hop)), PATH_USD, "hop bound to pathUSD");
    }

    /// @dev feeTokenOf tells integrators which token the two-argument mintRedeem will pull, so they can quote it.
    function testFork_E2E_FeeTokenOfView() public {
        assertEq(hop.feeTokenOf(user), PATH_USD, "unset -> pathUSD");
        assertEq(hop.feeTokenOf(address(new IntegratorCaller())), PATH_USD, "fresh contract -> pathUSD");
        vm.prank(user, user);
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(USDC_E);
        assertEq(hop.feeTokenOf(user), USDC_E, "set -> that token");
    }

    /// @dev Contract callers that never set a fee token are charged in pathUSD.
    function testFork_E2E_ContractCallerDefaultsToPathUsd() public {
        IntegratorCaller caller = new IntegratorCaller();
        vm.prank(FRXUSD_OFT);
        ITIP20(frxUsd).mint(address(caller), 20e6);
        vm.prank(user);
        IERC20Like(PATH_USD).transfer(address(caller), 2e6);

        uint256 amount = 10e6;
        bytes32 toC = bytes32(uint256(uint160(address(caller))));
        MessagingFee memory q = hop.quote(FRXUSD_OFT, toC, amount);
        uint256 cPath0 = _bal(PATH_USD, address(caller));
        caller.go(hop, FRXUSD_OFT, amount, PATH_USD, q.nativeFee);
        assertEq(cPath0 - _bal(PATH_USD, address(caller)), q.nativeFee, "contract caller paid in pathUSD");
        assertEq(_bal(frxUsd, address(caller)), 10e6, "contract caller bridged 10 frxUSD");
    }

    // ───────────────────────── negative paths ─────────────────────────

    function testFork_E2E_RevertsWithoutFeeAllowance() public {
        uint256 amount = 10e6;
        uint256 uFrx0 = _bal(frxUsd, user);
        vm.startPrank(user);
        ITIP20(frxUsd).approve(address(hop), amount);
        // no pathUSD approval
        vm.expectRevert();
        hop.mintRedeem(FRXUSD_OFT, amount);
        vm.stopPrank();
        assertEq(_bal(frxUsd, user), uFrx0, "revert is atomic: frxUSD not pulled");
    }

    function testFork_E2E_RevertsWithoutOftTokenAllowance() public {
        uint256 amount = 10e6;
        MessagingFee memory q = hop.quote(FRXUSD_OFT, to, amount);
        vm.startPrank(user);
        ITIP20(PATH_USD).approve(address(hop), q.nativeFee);
        vm.expectRevert();
        hop.mintRedeem(FRXUSD_OFT, amount);
        vm.stopPrank();
    }

    /// @dev Under Tempo EVM semantics a CALL carrying value fails before the contract's own msg.value guard.
    function testFork_E2E_ValueCallProbe() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool ok, ) = address(hop).call{ value: 1 }(abi.encodeCall(RemoteMintRedeemHop.mintRedeem, (FRXUSD_OFT, 1e6)));
        assertFalse(ok, "value call must fail");
    }

    /// @dev Owner sweep of the retained fee works on a TIP20 (raw IERC20.transfer returns bool).
    function testFork_E2E_OwnerRecoversRetainedFee() public {
        testFork_E2E_FrxUsd_PathUsdFee();
        uint256 retained = _bal(PATH_USD, address(hop));
        assertGt(retained, 0);
        uint256 msig0 = _bal(PATH_USD, TEMPO_MSIG);
        vm.prank(TEMPO_MSIG);
        vm.expectEmit(true, true, true, true, address(hop));
        emit RecoveredERC20(PATH_USD, TEMPO_MSIG, retained);
        hop.recoverERC20(PATH_USD, TEMPO_MSIG, retained);
        assertEq(_bal(PATH_USD, address(hop)), 0, "swept");
        assertEq(_bal(PATH_USD, TEMPO_MSIG) - msig0, retained, "landed with the recipient");
    }

    // ───────────────────────── book shaping (M-1 regression) ─────────────────────────

    /// @dev A maker funded with pathUSD (bids escrow the quote token) and a sweeper funded with frxUSD.
    function _fundBookShapers() internal returns (address maker, address sweeper) {
        maker = makeAddr("maker");
        sweeper = makeAddr("sweeper");

        // pathUSD has no public mint; borrow from the DEX's own escrow balance on the fork.
        vm.prank(DEX);
        (bool ok, ) = PATH_USD.call(abi.encodeCall(IERC20Like.transfer, (maker, uint256(3_000e6))));
        if (!ok) {
            console2.log("cannot source pathUSD for maker; skipping");
            vm.skip(true);
        }
        vm.prank(maker);
        ITIP20(PATH_USD).approve(DEX, type(uint256).max);

        vm.prank(FRXUSD_OFT);
        ITIP20(frxUsd).mint(sweeper, 5_000e6);
        vm.prank(sweeper);
        ITIP20(frxUsd).approve(DEX, type(uint256).max);
    }

    /// @dev Places two minimum-size bids at the top of the frxUSD book and partially fills the first down to
    ///      `r1` base units, so a fee-sized exact-out swap crosses the order boundary. Whether the per-order
    ///      rounding then exceeds the per-tick quote depends on (`needOut`, `r1`, price), so a handful of
    ///      shapes are tried; each candidate is verified by dry-running the un-padded swap the pre-fix hop
    ///      performed and checking for `MaxInputExceeded`. Leaves the first divergent book in place.
    function _shapeDivergentBook(
        address maker,
        address sweeper,
        uint128 needOut
    ) internal returns (bool found, address target, uint128 rawQuote) {
        int16[3] memory ticks = [int16(2000), 1990, 1980]; // best possible bids, so the swap hits our orders first
        uint128[8] memory r1s = [uint128(49), 25, 3, 1, 13, 37, 3333, 3334];

        for (uint256 t; t < ticks.length; ++t) {
            for (uint256 i; i < r1s.length; ++i) {
                uint256 shaped = vm.snapshotState();

                vm.startPrank(maker);
                StdPrecompiles.STABLECOIN_DEX.place(frxUsd, MIN_ORDER, true, ticks[t]);
                StdPrecompiles.STABLECOIN_DEX.place(frxUsd, MIN_ORDER, true, ticks[t]);
                vm.stopPrank();
                vm.prank(sweeper);
                StdPrecompiles.STABLECOIN_DEX.swapExactAmountIn(frxUsd, PATH_USD, MIN_ORDER - r1s[i], 0);

                (target, rawQuote) = _rawSwapQuote(frxUsd, needOut);

                uint256 dryRun = vm.snapshotState();
                vm.prank(sweeper);
                (bool ok, bytes memory data) = DEX.call(
                    abi.encodeCall(IStablecoinDEX.swapExactAmountOut, (frxUsd, target, needOut, rawQuote))
                );
                vm.revertToState(dryRun);

                if (!ok && bytes4(data) == IStablecoinDEX.MaxInputExceeded.selector) {
                    console2.log("divergent book: tick", uint256(int256(ticks[t])), "first-order remainder", r1s[i]);
                    return (true, target, rawQuote);
                }
                vm.revertToState(shaped);
            }
        }
        return (false, address(0), 0);
    }

    // ───────────────────────── helpers ─────────────────────────

    /// @dev Mirror of TempoGasTokenBase._findSwapTarget: the target the hop will pick and the un-padded quote.
    function _rawSwapQuote(
        address tokenIn,
        uint128 amountOut
    ) internal view returns (address target, uint128 amountIn) {
        address[] memory wl = lzd.getWhitelistedTokens();
        amountIn = type(uint128).max;
        for (uint256 i; i < wl.length; ++i) {
            if (wl[i] == tokenIn) continue;
            try StdPrecompiles.STABLECOIN_DEX.quoteSwapExactAmountOut(tokenIn, wl[i], amountOut) returns (uint128 q) {
                if (q < amountIn) {
                    amountIn = q;
                    target = wl[i];
                }
            } catch {}
        }
        require(target != address(0), "no swap route");
    }

    /// @dev Mirror of TempoGasTokenBase._withSlippage at the default allowance.
    function _padded(uint256 amountIn) internal pure returns (uint256 padded) {
        padded = (amountIn * (10_000 + DEFAULT_FEE_SWAP_SLIPPAGE_BPS)) / 10_000;
        if (padded <= amountIn) padded = amountIn + 1;
    }

    function _bal(address token, address who) internal view returns (uint256) {
        return IERC20Like(token).balanceOf(who);
    }

    function _peer(address oft) internal view returns (bytes32) {
        (bool ok, bytes memory data) = oft.staticcall(abi.encodeWithSignature("peers(uint32)", FRAXTAL_EID));
        require(ok, "peers");
        return abi.decode(data, (bytes32));
    }

    function _rpc() internal view returns (string memory rpcUrl) {
        rpcUrl = vm.envOr("TEMPO_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) rpcUrl = vm.envOr("TEMPO_MAINNET_URL", string(""));
        if (bytes(rpcUrl).length == 0) rpcUrl = "https://rpc.tempo.xyz";
    }
}
