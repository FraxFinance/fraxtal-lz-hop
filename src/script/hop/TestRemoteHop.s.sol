// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

/// @dev Minimal RemoteHop (v1) / FraxtalHop v1 interface
interface IRemoteHop {
    function sendOFT(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD) external payable;

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD
    ) external view returns (MessagingFee memory fee);
}

/// @title TestRemoteHop — Chained relay smoke test (RemoteHop v1)
///
/// @notice Sends all 6 FraxOFT assets from the deployer EOA on the current chain
///         to the deployer EOA on the destination chain via RemoteHop v1 / FraxtalHop v1.
///
///         This script is one STEP in a multi-chain relay round-trip. The shell script
///         test_remote_hop.sh sequences all steps and pauses for user confirmation
///         between each hop to wait for LayerZero delivery.
///
///         RELAY ORDER:
///           Fraxtal(252) → Arbitrum(42161) → Base(8453) → Optimism(10) → BSC(56) →
///           Unichain(130) → Sonic(146) → Worldchain(480) → ZkSync(324) → Abstract(2741) →
///           Mode(34443) → Ink(57073) → Linea(59144) → Scroll(534352) → XLayer(196) →
///           Avalanche(43114) → Berachain(80094) → Sei(1329) → Aurora(1313161554) →
///           Polygon(137) → Monad(143) → Plume(98866) → Katana(747474) →
///           Hyperliquid(999) → Ethereum(1) → Fraxtal(252)
///
///         MECHANICS:
///           • Fraxtal (chainId 252): FraxtalHop v1 is a receive-only composer — it has no
///             sendOFT. Outbound from Fraxtal uses IOFT.send() directly on each OFT adapter.
///             All token() and quoteSend() reads happen before vm.startBroadcast to avoid
///             Forge cold-call simulation issues (EvmError: NotActivated).
///           • Spoke chains: for each of 6 OFTs:
///               1. IERC20(token).approve(RemoteHop, TEST_AMOUNT)
///               2. RemoteHop.sendOFT{value:fee.nativeFee}(oft, dstEid, deployerB32, TEST_AMOUNT)
///             token() and quote() are resolved before vm.startBroadcast for the same reason.
///           Tokens must be held by the deployer EOA on each chain before the step runs.
///
///         REQUIRED ENV VARS:
///           PK      — deployer private key (holds OFTs on this chain)
///           DST_EID — LZ EID of destination chain
///
///         EXAMPLE (from fraxtal-lz-hop project root):
///           PK=$PK DST_EID=30110 \
///             forge script src/script/hop/TestRemoteHop.s.sol \
///             --rpc-url https://rpc.frax.com --broadcast
contract TestRemoteHop is Script {
    // ── FraxtalHop v1 ────────────────────────────────────────────────────────────────────
    address constant FRAXTAL_HOP = 0x2A2019b30C157dB6c1C01306b8025167dBe1803B;

    // ── RemoteHop v1 addresses per chain ────────────────────────────────────────────────
    // (from HopConstants.sol in fraxtal-lz-hop)
    address constant REMOTE_HOP_ETHEREUM      = 0x3ad4dC2319394bB4BE99A0e4aE2AbF7bCEbD648E;
    address constant REMOTE_HOP_OPTIMISM      = 0x31D982ebd82Ad900358984bd049207A4c2468640;
    address constant REMOTE_HOP_BSC           = 0x452420df4AC1e3db5429b5FD629f3047482C543C;
    address constant REMOTE_HOP_UNICHAIN      = 0xc71BF5Ee4740405030eF521F18A96eA14fec802D;
    address constant REMOTE_HOP_SONIC         = 0x3A5cDA3Ac66Aa80573402610c94B74eD6cdb2F23;
    address constant REMOTE_HOP_POLYGON       = 0xf74D38A26948E9DDa53eD85cF03C6b1188FbB30C;
    address constant REMOTE_HOP_XLAYER        = 0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396;
    address constant REMOTE_HOP_ZKSYNC        = 0xc5e4A0cfef8D801278927C25fB51C1DB7b69dDFb;
    address constant REMOTE_HOP_ABSTRACT      = 0xc5e4A0cfef8D801278927C25fB51C1DB7b69dDFb; // same as ZkSync
    address constant REMOTE_HOP_WORLDCHAIN    = 0x938d99A81814f66b01010d19DDce92A633441699;
    address constant REMOTE_HOP_BASE          = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address constant REMOTE_HOP_MODE          = 0x486CB4788F1bE7cdEf9301a7a637B451df3Cf262;
    address constant REMOTE_HOP_ARBITRUM      = 0x29F5DBD0FE72d8f11271FCBE79Cb87E18a83C70A;
    address constant REMOTE_HOP_AVALANCHE     = 0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A;
    address constant REMOTE_HOP_INK           = 0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A;
    address constant REMOTE_HOP_LINEA         = 0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876;
    address constant REMOTE_HOP_BERACHAIN     = 0xc71BF5Ee4740405030eF521F18A96eA14fec802D;
    address constant REMOTE_HOP_SCROLL        = 0xF6f45CCB5E85D1400067ee66F9e168f83e86124E;
    address constant REMOTE_HOP_MONAD         = 0x40F66FFf44DBBee88058185F2cFE287558D7E532;
    address constant REMOTE_HOP_SEI           = 0x3a6F28e8DDD232B02C72C491Bd1626F69D2fb329;
    address constant REMOTE_HOP_PLUME         = 0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876; // same as Linea
    address constant REMOTE_HOP_POLYGONZKEVM  = 0x111ddab65Af5fF96b674400246699ED40F550De1;
    address constant REMOTE_HOP_BLAST         = 0xe93Cb38f97469eac2f284a87813D0d701b28E58e;
    address constant REMOTE_HOP_KATANA        = 0x5d8EB59A12Bc98708702305A7b032f4b69Dd5b5c;
    address constant REMOTE_HOP_HYPERLIQUID   = 0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2;
    address constant REMOTE_HOP_AURORA        = 0x53e36C8380Ff62D7964BFa4868A0045E58A52344;

    // ── LZ EIDs ──────────────────────────────────────────────────────────────────────────
    uint32 constant EID_FRAXTAL     = 30_255;
    uint32 constant EID_ETHEREUM    = 30_101;
    uint32 constant EID_ARBITRUM    = 30_110;
    uint32 constant EID_BASE        = 30_184;
    uint32 constant EID_OPTIMISM    = 30_111;
    uint32 constant EID_BSC         = 30_102;
    uint32 constant EID_AVALANCHE   = 30_106;
    uint32 constant EID_LINEA       = 30_183;
    uint32 constant EID_SCROLL      = 30_214;
    uint32 constant EID_SONIC       = 30_332;
    uint32 constant EID_MODE        = 30_260;
    uint32 constant EID_INK         = 30_339;
    uint32 constant EID_UNICHAIN    = 30_320;
    uint32 constant EID_WORLDCHAIN  = 30_319;
    uint32 constant EID_XLAYER      = 30_274;
    uint32 constant EID_ZKSYNC      = 30_165;
    uint32 constant EID_ABSTRACT    = 30_324;
    uint32 constant EID_BERACHAIN   = 30_362;
    uint32 constant EID_MONAD       = 30_390;
    uint32 constant EID_SEI         = 30_280;
    uint32 constant EID_POLYGON     = 30_109;
    uint32 constant EID_PLUME       = 30_370; // plumephoenix chainId 98866
    uint32 constant EID_POLYGONZKEVM = 30_158;
    uint32 constant EID_BLAST       = 30_243;
    uint32 constant EID_KATANA      = 30_375;
    uint32 constant EID_HYPERLIQUID = 30_367;
    uint32 constant EID_AURORA      = 30_211;

    // ── Fraxtal lockbox OFTs ──────────────────────────────────────────────────────────────
    address constant FRAXTAL_FRXUSD_OFT  = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address constant FRAXTAL_SFRXUSD_OFT = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address constant FRAXTAL_FRXETH_OFT  = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address constant FRAXTAL_SFRXETH_OFT = 0x75c38D46001b0F8108c4136216bd2694982C20FC;
    address constant FRAXTAL_WFRAX_OFT   = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address constant FRAXTAL_FPI_OFT     = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;

    // ── Ethereum adapters ─────────────────────────────────────────────────────────────────
    address constant ETH_FRXUSD_OFT  = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0;
    address constant ETH_SFRXUSD_OFT = 0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126;
    address constant ETH_FRXETH_OFT  = 0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6;
    address constant ETH_SFRXETH_OFT = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960;
    address constant ETH_WFRAX_OFT   = 0x04ACaF8D2865c0714F79da09645C13FD2888977f;
    address constant ETH_FPI_OFT     = 0x9033BAD7aA130a2466060A2dA71fAe2219781B4b;

    // ── Base OFTs ─────────────────────────────────────────────────────────────────────────
    address constant BASE_FRXUSD_OFT  = 0xe5020A6d073a794B6E7f05678707dE47986Fb0b6;
    address constant BASE_SFRXUSD_OFT = 0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e;
    address constant BASE_FRXETH_OFT  = 0x7eb8d1E4E2D0C8b9bEDA7a97b305cF49F3eeE8dA;
    address constant BASE_SFRXETH_OFT = 0x192e0C7Cc9B263D93fa6d472De47bBefe1Fb12bA;
    address constant BASE_WFRAX_OFT   = 0x0CEAC003B0d2479BebeC9f4b2EBAd0a803759bbf;
    address constant BASE_FPI_OFT     = 0xEEdd3A0DDDF977462A97C1F0eBb89C3fbe8D084B;

    // ── Linea OFTs ────────────────────────────────────────────────────────────────────────
    address constant LINEA_FRXUSD_OFT  = 0xC7346783f5e645aa998B106Ef9E7f499528673D8;
    address constant LINEA_SFRXUSD_OFT = 0x592a48c0FB9c7f8BF1701cB0136b90DEa2A5B7B6;
    address constant LINEA_FRXETH_OFT  = 0xB1aFD04774c02AE84692619448B08BA79F19b1ff;
    address constant LINEA_SFRXETH_OFT = 0x383Eac7CcaA89684b8277cBabC25BCa8b13B7Aa2;
    address constant LINEA_WFRAX_OFT   = 0x5217Ab28ECE654Aab2C68efedb6A22739df6C3D5;
    address constant LINEA_FPI_OFT     = 0xDaF72Aa849d3C4FAA8A9c8c99f240Cf33dA02fc4;

    // ── Scroll OFTs ───────────────────────────────────────────────────────────────────────
    address constant SCROLL_FRXUSD_OFT  = 0x397F939C3b91A74C321ea7129396492bA9Cdce82;
    address constant SCROLL_SFRXUSD_OFT = 0xC6B2BE25d65760B826D0C852FD35F364250619c2;
    address constant SCROLL_FRXETH_OFT  = 0x0097Cf8Ee15800d4f80da8A6cE4dF360D9449Ed5;
    address constant SCROLL_SFRXETH_OFT = 0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE;
    address constant SCROLL_WFRAX_OFT   = 0x879BA0EFE1AB0119FefA745A21585Fa205B07907;
    address constant SCROLL_FPI_OFT     = 0x93cDc5d29293Cb6983f059Fec6e4FFEb656b6a62;

    // ── ZkSync & Abstract OFTs (same addresses on both chains) ────────────────────────────
    address constant ZK_FRXUSD_OFT  = 0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d;
    address constant ZK_SFRXUSD_OFT = 0x9F87fbb47C33Cd0614E43500b9511018116F79eE;
    address constant ZK_FRXETH_OFT  = 0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440;
    address constant ZK_SFRXETH_OFT = 0xFD78FD3667DeF2F1097Ed221ec503AE477155394;
    address constant ZK_WFRAX_OFT   = 0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F;
    address constant ZK_FPI_OFT     = 0x580F2ee1476eDF4B1760bd68f6AaBaD57dec420E;

    // ── Default spoke OFTs ────────────────────────────────────────────────────────────────
    address constant SPOKE_FRXUSD_OFT  = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address constant SPOKE_SFRXUSD_OFT = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address constant SPOKE_FRXETH_OFT  = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address constant SPOKE_SFRXETH_OFT = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address constant SPOKE_WFRAX_OFT   = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address constant SPOKE_FPI_OFT     = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    // ── Monad OFTs (unique addresses) ──────────────────────────────────────────────
    address constant MONAD_FRXUSD_OFT  = 0x58E3ee6accd124642dDB5d3f91928816Be8D8ed3;
    address constant MONAD_SFRXUSD_OFT = 0x137643F7b2C189173867b3391f6629caB46F0F1a;
    address constant MONAD_FRXETH_OFT  = 0x288F9D76019469bfEb56BB77d86aFa2bF563B75B;
    address constant MONAD_SFRXETH_OFT = 0x3B4cf37A3335F21c945a40088404c715525fCb29;
    address constant MONAD_WFRAX_OFT   = 0x29aCC7c504665A5EA95344796f784095f0cfcC58;
    address constant MONAD_FPI_OFT     = 0xBa554F7A47f0792b9fa41A1256d4cf628Bb1D028;
    // 0.00001 ether — dust amount sufficient to verify routing
    uint256 constant TEST_AMOUNT = 0.00001 ether; // 1e13;

    // ─────────────────────────────────────────────────────────────────────────────────────

    function _remoteHop(uint256 chainId) internal pure returns (address) {
        if (chainId ==           1) return REMOTE_HOP_ETHEREUM;
        if (chainId ==          10) return REMOTE_HOP_OPTIMISM;
        if (chainId ==          56) return REMOTE_HOP_BSC;
        if (chainId ==         130) return REMOTE_HOP_UNICHAIN;
        if (chainId ==         137) return REMOTE_HOP_POLYGON;
        if (chainId ==         143) return REMOTE_HOP_MONAD;
        if (chainId ==         146) return REMOTE_HOP_SONIC;
        if (chainId ==         196) return REMOTE_HOP_XLAYER;
        if (chainId ==         324) return REMOTE_HOP_ZKSYNC;
        if (chainId ==         480) return REMOTE_HOP_WORLDCHAIN;
        if (chainId ==         999) return REMOTE_HOP_HYPERLIQUID;
        if (chainId ==       1_101) return REMOTE_HOP_POLYGONZKEVM;
        if (chainId ==       1_329) return REMOTE_HOP_SEI;
        if (chainId ==       2_741) return REMOTE_HOP_ABSTRACT;
        if (chainId ==       8_453) return REMOTE_HOP_BASE;
        if (chainId ==      34_443) return REMOTE_HOP_MODE;
        if (chainId ==      42_161) return REMOTE_HOP_ARBITRUM;
        if (chainId ==      43_114) return REMOTE_HOP_AVALANCHE;
        if (chainId ==      57_073) return REMOTE_HOP_INK;
        if (chainId ==      59_144) return REMOTE_HOP_LINEA;
        if (chainId ==      80_094) return REMOTE_HOP_BERACHAIN;
        if (chainId ==      81_457) return REMOTE_HOP_BLAST;
        if (chainId ==      98_866) return REMOTE_HOP_PLUME;
        if (chainId ==     534_352) return REMOTE_HOP_SCROLL;
        if (chainId ==     747_474) return REMOTE_HOP_KATANA;
        if (chainId == 1_313_161_554) return REMOTE_HOP_AURORA;
        revert("TestRemoteHop: no RemoteHop v1 for this chain");
    }

    function _ofts(uint256 chainId) internal pure returns (address[6] memory) {
        if (chainId ==     252) return [FRAXTAL_FRXUSD_OFT, FRAXTAL_SFRXUSD_OFT, FRAXTAL_FRXETH_OFT, FRAXTAL_SFRXETH_OFT, FRAXTAL_WFRAX_OFT, FRAXTAL_FPI_OFT];
        if (chainId ==       1) return [ETH_FRXUSD_OFT,     ETH_SFRXUSD_OFT,     ETH_FRXETH_OFT,     ETH_SFRXETH_OFT,     ETH_WFRAX_OFT,     ETH_FPI_OFT];
        if (chainId ==     143) return [MONAD_FRXUSD_OFT,   MONAD_SFRXUSD_OFT,   MONAD_FRXETH_OFT,   MONAD_SFRXETH_OFT,   MONAD_WFRAX_OFT,   MONAD_FPI_OFT];
        if (chainId ==   8_453) return [BASE_FRXUSD_OFT,    BASE_SFRXUSD_OFT,    BASE_FRXETH_OFT,    BASE_SFRXETH_OFT,    BASE_WFRAX_OFT,    BASE_FPI_OFT];
        if (chainId ==  59_144) return [LINEA_FRXUSD_OFT,   LINEA_SFRXUSD_OFT,   LINEA_FRXETH_OFT,   LINEA_SFRXETH_OFT,   LINEA_WFRAX_OFT,   LINEA_FPI_OFT];
        if (chainId == 534_352) return [SCROLL_FRXUSD_OFT,  SCROLL_SFRXUSD_OFT,  SCROLL_FRXETH_OFT,  SCROLL_SFRXETH_OFT,  SCROLL_WFRAX_OFT,  SCROLL_FPI_OFT];
        if (chainId == 324 || chainId == 2_741) return [ZK_FRXUSD_OFT, ZK_SFRXUSD_OFT, ZK_FRXETH_OFT, ZK_SFRXETH_OFT, ZK_WFRAX_OFT, ZK_FPI_OFT];
        return [SPOKE_FRXUSD_OFT, SPOKE_SFRXUSD_OFT, SPOKE_FRXETH_OFT, SPOKE_SFRXETH_OFT, SPOKE_WFRAX_OFT, SPOKE_FPI_OFT];
    }

    function run() external {
        uint256 pk       = vm.envUint("PK");
        address deployer = vm.addr(pk);
        uint32  dstEid   = uint32(vm.envUint("DST_EID"));

        bytes32 deployerB32    = bytes32(uint256(uint160(deployer)));
        address[6] memory ofts = _ofts(block.chainid);

        console.log("=== TestRemoteHop v1 step ===");
        console.log("srcChainId :", block.chainid);
        console.log("dstEid     :", dstEid);
        console.log("deployer   :", deployer);
        console.log("amount     :", TEST_AMOUNT);

        if (block.chainid == 252) {
            // ── Fraxtal: send directly via IOFT.send() ────────────────────────────────
            // FraxtalHop v1 is a receive-only IOAppComposer and has no sendOFT function.
            // Outbound from Fraxtal goes direct via the lockbox OFT adapter.
            // Resolve token addresses and fees BEFORE vm.startBroadcast to avoid
            // EvmError: NotActivated on cold contract reads in broadcast simulation.
            SendParam[6]    memory sendParams;
            MessagingFee[6] memory fees;
            address[6]      memory tokens;

            for (uint256 i = 0; i < 6; i++) {
                tokens[i]     = IOFT(ofts[i]).token();
                sendParams[i] = SendParam({
                    dstEid:       dstEid,
                    to:           deployerB32,
                    amountLD:     TEST_AMOUNT,
                    minAmountLD:  0,
                    extraOptions: "",
                    composeMsg:   "",
                    oftCmd:       ""
                });
                fees[i] = IOFT(ofts[i]).quoteSend(sendParams[i], false);
            }

            vm.startBroadcast(pk);
            for (uint256 i = 0; i < 6; i++) {
                IERC20(tokens[i]).approve(ofts[i], TEST_AMOUNT);
                IOFT(ofts[i]).send{ value: fees[i].nativeFee }(sendParams[i], fees[i], deployer);
            }
            vm.stopBroadcast();

        } else {
            // ── Spoke chains: approve RemoteHop and call sendOFT ───────────────────────
            // Resolve token addresses and fees before broadcast (same reason as above).
            address hopAddr = _remoteHop(block.chainid);
            IRemoteHop hop  = IRemoteHop(hopAddr);

            console.log("hopAddr    :", hopAddr);

            address[6]      memory tokens;
            MessagingFee[6] memory fees;

            for (uint256 i = 0; i < 6; i++) {
                tokens[i] = IOFT(ofts[i]).token();
                fees[i]   = hop.quote(ofts[i], dstEid, deployerB32, TEST_AMOUNT);
            }

            vm.startBroadcast(pk);
            for (uint256 i = 0; i < 6; i++) {
                IERC20(tokens[i]).approve(hopAddr, TEST_AMOUNT);
                hop.sendOFT{ value: fees[i].nativeFee }(ofts[i], dstEid, deployerB32, TEST_AMOUNT);
            }
            vm.stopBroadcast();
        }
    }
}
