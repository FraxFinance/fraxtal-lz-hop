// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { console } from "forge-std/Script.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { DeployRemoteHop, IExecutor, ISendLibrary } from "./DeployRemoteHop.sol";
import { RemoteMintRedeemHopTempo } from "src/contracts/hop/RemoteMintRedeemHopTempo.sol";

interface IOFTToken {
    function token() external view returns (address);
}

// @dev Tempo's endpoint is an EndpointV2Alt that charges fees in an ERC20 (LZD, 6 decimals), so this
//      chain gets `RemoteMintRedeemHopTempo` rather than the stock hop -- the native `send{value:}` and
//      refund paths would revert on every mintRedeem().
// @dev `--evm-version shanghai` is required, as on the other recent chains: the mesh OFT proxies
//      contain PUSH0, which the repo default `paris` rejects with `NotActivated` during simulation.
//
// Dry run:  forge script src/script/hop/Remote/DeployRemoteHopTempo.sol --rpc-url https://rpc.tempo.xyz --evm-version shanghai --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc
// Broadcast: forge script src/script/hop/Remote/DeployRemoteHopTempo.sol --rpc-url https://rpc.tempo.xyz --evm-version shanghai --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast
contract DeployRemoteHopTempo is DeployRemoteHop {
    address constant TEMPO_ENDPOINT = 0x20Bb7C2E2f4e5ca2B4c57060d1aE2615245dCc9C;

    constructor() {
        EXECUTOR = 0xf851abCa1d0fD1Df8eAba6de466a102996b7d7B2;
        DVN = 0x76FaFF60799021B301B45dC1BbEDE53F261F9961;
        SEND_LIBRARY = 0x572863d9247E52026E0892d9Cd2E519B41EdB73C;

        owner = 0x1Ba19a54a01AE967f5E3895764Caaa6919FD2bEe;

        // Fraxtal -> Tempo (eid 30410) is configured with 5 required DVNs
        numDVNs = 5;

        frxUsdOft = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
        sfrxUsdOft = 0x00000000fD8C4B8A413A06821456801295921a71;
        frxEthOft = 0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c;
        sfrxEthOft = 0x00000000883279097A49dB1f2af954EAd0C77E3c;
        wFraxOft = 0x00000000E9CE0f293D1Ce552768b187eBA8a56D4;
        fpiOft = 0x00000000bC4aEF4bA6363a437455Cb1af19e2aEb;
    }

    function run() public override {
        _validateAddrs();

        vm.startBroadcast();

        RemoteMintRedeemHopTempo remoteMintRedeemHop = new RemoteMintRedeemHopTempo({
            _owner: owner,
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_MINTREDEEM_HOP))),
            _numDVNs: numDVNs,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: ISendLibrary(SEND_LIBRARY).treasury(),
            _EID: IExecutor(EXECUTOR).localEidV2(),
            _frxUsdOft: frxUsdOft,
            _sfrxUsdOft: sfrxUsdOft,
            _endpoint: TEMPO_ENDPOINT
        });
        console.log("RemoteMintRedeemHopTempo deployed at:", address(remoteMintRedeemHop));
        // Register this address as remoteHop[30410] on the Fraxtal hub (ConnectFraxtalMintRedeemHop) right
        // away: until then a hop lands on the hub with InvalidSourceChain and waits there for the wiring.

        vm.stopBroadcast();
    }

    function _validateAddrs() internal view override returns (bool) {
        require(IExecutor(EXECUTOR).endpoint() == TEMPO_ENDPOINT, "EXECUTOR endpoint != TEMPO_ENDPOINT");
        return super._validateAddrs();
    }

    /// @dev Tempo's frxUSD OFT is a TIP20 adapter: `symbol()` reverts on the OFT and only the
    ///      underlying TIP20 carries it. Fall back to the underlying so the sanity checks still run.
    function _oftSymbol(address _oft) internal view override returns (string memory) {
        try IERC20Metadata(_oft).symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            return IERC20Metadata(IOFTToken(_oft).token()).symbol();
        }
    }
}
