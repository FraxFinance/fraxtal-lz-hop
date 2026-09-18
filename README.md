## Specification
### RemoteHop
**Purpose:** User wants to move [(s)frxUSD, (s)frxETH, FXS, FPI] from chain A to chain B via LZ.
1. User sends OFT to RemoteHop on Chain A
   - If `Chain B == Fraxtal`
        1. Chain A RemoteHop sends OFT to recipient on Fraxtal
   - If `Chain B != Fraxtal`
       1. Chain A RemoteHop sends OFT to Fraxtal Remotehop
        2. Fraxtal Remotehop sends OFT to recipient on chain B.

### MintRedeemHop
**Purpose:** User wants to convert their frxUSD to sfrxUSD (or vise versa) on chain A at the best provided rate
1. User sends OFT to MintRedeemHop on chain A
3. Chain A MintRedeemHop sends OFT to Fraxtal MintRedeemHop
4. Fraxtal MintRedeemHop either deposits or redeems (depending if the OFT is frxUSD or sfrxUSD) to the alternate OFT
5. Fraxtal MintRedeemHop sends newly received token back to user on chain A

## How to use
### Interfaces
```Solidity
interface IERC20 {
    function approve(address spender, uint256 amount) external;
}
interface IOFT {
    function token() external view returns (address);
}
struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}
interface IRemoteHop {
    function quote(address oft, uint32 dstEid, bytes32 toAsBytes32, uint256 amount) external view returns (MessagingFee memory fee);
    function sendOFT(address oft, uint32 dstEid, bytes32 toAsBytes23, uint256 amount) external payable;
}
interface IMintRedeemHop {
    function quote(address oft, bytes32 toAsBytes32, uint256 amount) external view returns (MessagingFee memory fee);
    function mintRedeem(address oft, uint256 amount) external payable;
}
// Tempo only (RemoteMintRedeemHopTempo): fees are paid in a TIP20, never in msg.value
interface IMintRedeemHopTempo is IMintRedeemHop {
    function feeTokenOf(address caller) external view returns (address);
    function quoteUserTokenFee(address oft, bytes32 toAsBytes32, uint256 amount, address feeToken) external view returns (uint256);
    function mintRedeem(address oft, uint256 amount, address feeToken, uint256 maxFeeTokenAmount) external;
}
```

### RemoteHop
```Solidity
// Ethereum WFRAX => (Fraxtal) => Sonic WFRAX

// OFT address found @ https://docs.frax.com/protocol/crosschain/addresses
address oft = 0x04ACaF8D2865c0714F79da09645C13FD2888977f; // WFRAX OFT
address remoteHop = 0x3ad4dC2319394bB4BE99A0e4aE2AbF7bCEbD648E; // See deployed contracts below
uint256 amount = 1e18;
uint32 dstEid = 30332; // Sonic
bytes32 to = bytes32(uint256(uint160(0xb0E1650A9760e0f383174af042091fc544b8356f))); // example

// 1. Quote cost of send
MessagingFee memory fee = IRemoteHop(remoteHop).quote(oft, dstEid, to, amount);

// 2. Approve OFT underlying token to be transferred to the remoteHop 
IERC20(IOFT(oft).token()).approve(remoteHop, amount);

// 3. Send the OFT to destination
IRemoteHop(remoteHop).sendOFT{value: fee.nativeFee}(oft, dstEid, to, amount);
```

### MintRedeemHop
```Solidity
// Sonic frxUSD => (Fraxtal) => Sonic sfrxUSD

// OFT address found @ https://docs.frax.com/protocol/crosschain/addresses
address oft = 0x80Eede496655FB9047dd39d9f418d5483ED600df; // frxUSD OFT
address mintRedeemHop = 0xf6115Bb9b6A4b3660dA409cB7afF1fb773efaD0b; // see deployed contracts below
uint256 amount = 1e18;
bytes32 to = bytes32(uint256(uint160(0xb0E1650A9760e0f383174af042091fc544b8356f))); // example

// 1. Quote cost of send
MessagingFee memory fee = IMintRedeemHop(mintRedeemHop).quote(oft, to, amount);

// 2. Approve OFT underlying token to be transferred to the mintRedeemHop
IERC20(IOFT(oft).token()).approve(mintRedeemHop, amount);

// 3. Convert the frxUSD to sfrxUSD
IMintRedeemHop(mintRedeemHop).mintRedeem{value: fee.nativeFee}(oft, amount);
```

### MintRedeemHop on Tempo
Tempo's LayerZero endpoint is an `EndpointV2Alt`: message fees are charged in an ERC20 (`LZEndpointDollar`, 6 decimals), not in gas. The Tempo hop (`RemoteMintRedeemHopTempo`) therefore takes no `msg.value` — a value-carrying call reverts — and pulls the fee from the caller as a TIP20 instead. Everything else (the Fraxtal round trip, the recipient being `msg.sender`) is the same as on the other chains.

- **Fee token.** A TIP20 that LayerZero whitelists (pathUSD `0x20C0…0000`, USDC.e, USDT0 today) is pulled 1:1. Any other TIP20 (e.g. frxUSD) is swapped on Tempo's StablecoinDEX into the cheapest whitelisted one, so it needs a live route there and carries a small swap headroom (default 50 bps, at least 1 unit) that is refunded in the same call; with no route the call reverts `NoSwappableWhitelistedToken`.
- **Quote in the fee token.** `quote(oft, to, amount).nativeFee` is in LZEndpointDollar units (6 decimals). Use `quoteUserTokenFee(oft, to, amount, feeToken)` for the figure in the token you will actually pay with — it already includes the headroom and is the most the hop will debit.
- **Two approvals.** The bridged token (`IOFT(oft).token()`) for `amount`, and the fee token for the quoted fee. If they are the same token (frxUSD paying in frxUSD), approve `amount + fee` once.
- **Use the capped overload.** `mintRedeem(oft, amount, feeToken, maxFeeTokenAmount)` reverts `FeeAboveCap` before pulling anything if the live fee in `feeToken` exceeds the cap — the Tempo equivalent of the `msg.value` ceiling. The two-argument `mintRedeem(oft, amount)` still exists for ABI compatibility, but it pays in `feeTokenOf(caller)` (the caller's FeeManager fee token, pathUSD if unset) with no cap other than the ERC20 allowance.
- **Decimals.** Amounts are in the OFT's own decimals: Tempo frxUSD is a 6-decimal TIP20 adapter, Tempo sfrxUSD a normal 18-decimal OFT.

```Solidity
// Tempo frxUSD => (Fraxtal) => Tempo sfrxUSD, fee paid in pathUSD

address oft = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;      // frxUSD OFT on Tempo (TIP20 adapter, 6 decimals)
address mintRedeemHop = 0xD512291495ADDBcEC271b5FF802868F5d2f7f83F; // RemoteMintRedeemHopTempo, see deployed contracts below
address feeToken = 0x20C0000000000000000000000000000000000000; // pathUSD (LZ-whitelisted: pulled 1:1, no swap)
uint256 amount = 1e6;                                          // 1 frxUSD
bytes32 to = bytes32(uint256(uint160(msg.sender)));            // the hop always returns the tokens to msg.sender

// 1. Quote the fee in the token you will pay with (LZ send fee + retained return-leg fee)
uint256 maxFee = IMintRedeemHopTempo(mintRedeemHop).quoteUserTokenFee(oft, to, amount, feeToken);

// 2. Approve the bridged token and the fee token
IERC20(IOFT(oft).token()).approve(mintRedeemHop, amount);
IERC20(feeToken).approve(mintRedeemHop, maxFee);

// 3. Convert. No msg.value; reverts FeeAboveCap (nothing pulled) if the live fee exceeds maxFee
IMintRedeemHopTempo(mintRedeemHop).mintRedeem(oft, amount, feeToken, maxFee);
```

## Deployed Contracts
### HopV2 Mainnet
| Chain | `Hop` | `RemoteAdmin` |
| --- | --- | --- |
| Fraxtal | [`0xe8Cd13de17CeC6FCd9dD5E0a1465Da240f951536`](https://fraxscan.com/address/0xe8Cd13de17CeC6FCd9dD5E0a1465Da240f951536) | [`0xDC3369C18Ff9C077B803C98b6260a186aDE9A426`](https://fraxscan.com/address/0xDC3369C18Ff9C077B803C98b6260a186aDE9A426) |
| Arbitrum | [`0xf307Ad241E1035062Ed11F444740f108B8D036a6`](https://arbiscan.io/address/0xf307Ad241E1035062Ed11F444740f108B8D036a6) | [`0x03047fA366900b4cBf5E8F9FEEce97553f20370e`](https://arbiscan.io/address/0x03047fA366900b4cBf5E8F9FEEce97553f20370e) |
| Base | [`0x22beDD55A0D29Eb31e75C70F54fADa7Ca94339B9`](https://basescan.org/address/0x22beDD55A0D29Eb31e75C70F54fADa7Ca94339B9) | [`0xF333d66C7e47053b96bC153Bfdfaa05c8BEe7307`](https://basescan.org/address/0xF333d66C7e47053b96bC153Bfdfaa05c8BEe7307) |
| Ethereum | [`0xFd3B410b82a00B2651b42A13837204c5e3D92e27`](https://etherscan.io/address/0xFd3B410b82a00B2651b42A13837204c5e3D92e27) | [`0xa2db46c06e0B643A926ef60d1fEB744A7385a593`](https://etherscan.io/address/0xa2db46c06e0B643A926ef60d1fEB744A7385a593) |


### Mainnet
| Chain | `RemoteHop` | `MintRedeemHop` |
| --- | ---| ---|
| Fraxtal | [`0x2A2019b30C157dB6c1C01306b8025167dBe1803B`](https://fraxscan.com/address/0x2A2019b30C157dB6c1C01306b8025167dBe1803B) | [`0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC`](https://fraxscan.com/address/0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC) |
| Sonic | [`0x3A5cDA3Ac66Aa80573402610c94B74eD6cdb2F23`](https://sonicscan.org/address/0x3A5cDA3Ac66Aa80573402610c94B74eD6cdb2F23) | [`0xf6115Bb9b6A4b3660dA409cB7afF1fb773efaD0b`](https://sonicscan.org/address/0xf6115Bb9b6A4b3660dA409cB7afF1fb773efaD0b) |
| Ethereum | [`0x3ad4dC2319394bB4BE99A0e4aE2AbF7bCEbD648E`](https://etherscan.io/address/0x3ad4dC2319394bB4BE99A0e4aE2AbF7bCEbD648E) | [`0x99B5587ab54A49e3F827D10175Caf69C0187bfA8`](https://etherscan.io/address/0x99B5587ab54A49e3F827D10175Caf69C0187bfA8) |
| Sei | [`0x3a6F28e8DDD232B02C72C491Bd1626F69D2fb329`](https://seitrace.com/address/0x3a6F28e8DDD232B02C72C491Bd1626F69D2fb329?chain=pacific-1) | [`0x0255a172d0a060F2bEab3e7c12334dD73cCC26ba`](https://seitrace.com/address/0x0255a172d0a060F2bEab3e7c12334dD73cCC26ba?chain=pacific-1) |
| Linea | [`0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876`](https://lineascan.build/address/0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876) | [`0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb`](https://lineascan.build/address/0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb) |
| Mode | [`0x486CB4788F1bE7cdEf9301a7a637B451df3Cf262`](https://explorer.mode.network/address/0x486cb4788f1be7cdef9301a7a637b451df3cf262) | [`0x7360575f6f8F91b38dD078241b0Df508f5fBfDf9`](https://explorer.mode.network/address/0x7360575f6f8f91b38dd078241b0df508f5fbfdf9) |
| X-Layer | [`0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396`](https://www.oklink.com/x-layer/address/0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396) | [`0x45c6852A5188Ce1905567EA83454329bd4982007`](https://www.oklink.com/x-layer/address/0x45c6852a5188ce1905567ea83454329bd4982007) |
| Ink | [`0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A`](https://explorer.inkonchain.com/address/0x7a07d606c87b7251c2953a30fa445d8c5f856c7a) | [`0x452420df4AC1e3db5429b5FD629f3047482C543C`](https://explorer.inkonchain.com/address/0x452420df4AC1e3db5429b5FD629f3047482C543C) |
| Arbitrum | [`0x29F5DBD0FE72d8f11271FCBE79Cb87E18a83C70A`](https://arbiscan.io/address/0x29f5dbd0fe72d8f11271fcbe79cb87e18a83c70a) | [`0xa46A266dCBf199a71532c76967e200994C5A0D6d`](https://arbiscan.io/address/0xa46A266dCBf199a71532c76967e200994C5A0D6d) |
| Optimism | [`0x31D982ebd82Ad900358984bd049207A4c2468640`](https://optimistic.etherscan.io/address/0x31d982ebd82ad900358984bd049207a4c2468640) | [`0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A`](https://optimistic.etherscan.io/address/0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A) |
| Polygon | [`0xf74D38A26948E9DDa53eD85cF03C6b1188FbB30C`](https://polygonscan.com/address/0xf74D38A26948E9DDa53eD85cF03C6b1188FbB30C) | [`0x5658e82E330e094627D9b362ed0E137eA06673C4`](https://polygonscan.com/address/0x5658e82E330e094627D9b362ed0E137eA06673C4) |
| Avalanche | [`0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A`](https://snowtrace.io/address/0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A) | [`0x452420df4AC1e3db5429b5FD629f3047482C543C`](https://snowtrace.io/address/0x452420df4AC1e3db5429b5FD629f3047482C543C) |
| BSC | [`0x452420df4AC1e3db5429b5FD629f3047482C543C`](https://bscscan.com/address/0x452420df4AC1e3db5429b5FD629f3047482C543C) | [`0xdee45510b42Cb0678C8A61D043C698aF66b0d852`](https://bscscan.com/address/0xdee45510b42Cb0678C8A61D043C698aF66b0d852) |
| Polygon ZkEvm | [`0x111ddab65Af5fF96b674400246699ED40F550De1`](https://zkevm.polygonscan.com/address/0x111ddab65Af5fF96b674400246699ED40F550De1) | [`0xc71BF5Ee4740405030eF521F18A96eA14fec802D`](https://zkevm.polygonscan.com/address/0xc71BF5Ee4740405030eF521F18A96eA14fec802D) |
| Blast | [`0xe93Cb38f97469eac2f284a87813D0d701b28E58e`](https://blastscan.io/address/0xe93Cb38f97469eac2f284a87813D0d701b28E58e) | [`0x85b1714b25f40FD5025423124c076476073180b3`](https://blastscan.io/address/0x85b1714b25f40FD5025423124c076476073180b3) |
| Base | [`0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45`](https://basescan.org/address/0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45) | [`0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE`](https://basescan.org/address/0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE) |
| Berachain | [`0xc71BF5Ee4740405030eF521F18A96eA14fec802D`](https://berascan.com/address/0xc71BF5Ee4740405030eF521F18A96eA14fec802D) | [`0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263`](https://berascan.com/address/0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263) |
| Abstract | [`0xc5e4a0cfef8d801278927c25fb51c1db7b69ddfb`](https://abscan.org/address/0xc5e4a0cfef8d801278927c25fb51c1db7b69ddfb) | [`0xa05e9f9b97c963b5651ed6a50fae46625a8c400b`](https://abscan.org/address/0xa05e9f9b97c963b5651ed6a50fae46625a8c400b) |
| ZkSync | [`0xc5e4a0cfef8d801278927c25fb51c1db7b69ddfb`](https://era.zksync.network/address/0xc5e4a0cfef8d801278927c25fb51c1db7b69ddfb) | [`0xa05e9f9b97c963b5651ed6a50fae46625a8c400b`](https://era.zksync.network/address/0xa05e9f9b97c963b5651ed6a50fae46625a8c400b) |
| Worldchain | [`0x938d99A81814f66b01010d19DDce92A633441699`](https://worldscan.org/address/0x938d99A81814f66b01010d19DDce92A633441699) | [`0x111ddab65Af5fF96b674400246699ED40F550De1`](https://worldscan.org/address/0x111ddab65Af5fF96b674400246699ED40F550De1) |
| Unichain | [`0xc71BF5Ee4740405030eF521F18A96eA14fec802D`](https://uniscan.xyz/address/0xc71BF5Ee4740405030eF521F18A96eA14fec802D) | [`0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263`](https://uniscan.xyz/address/0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263) |
| Plume | [`0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876`](https://explorer.plume.org/address/0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876) | [`0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb`](https://explorer.plume.org/address/0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb) |
|Scroll|[`0xF6f45CCB5E85D1400067ee66F9e168f83e86124E`](https://scrollscan.com/address/0xf6f45ccb5e85d1400067ee66f9e168f83e86124e)|[`0x91DDB0E0C36B901C6BF53B9Eb5ACa0Eb1465F558`](https://scrollscan.com/address/0x91ddb0e0c36b901c6bf53b9eb5aca0eb1465f558)|
|Aurora|[`0x53e36c8380ff62d7964bfa4868a0045e58a52344`](https://explorer.aurora.dev/address/0x53e36C8380Ff62D7964BFa4868A0045E58A52344)|[`0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2`](https://explorer.aurora.dev/address/0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2)|
| Katana | [`0x5d8EB59A12Bc98708702305A7b032f4b69Dd5b5c`](https://explorer.katanarpc.com/address/0x5d8EB59A12Bc98708702305A7b032f4b69Dd5b5c) | [`0xF6f45CCB5E85D1400067ee66F9e168f83e86124E`](https://explorer.katanarpc.com/address/0xF6f45CCB5E85D1400067ee66F9e168f83e86124E) |
| Hyperliquid | [`0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2`](https://hyperevmscan.io/address/0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2) | [`0xb85A8FDa7F5e52E32fa5582847CFfFee9456a5Dc`](https://hyperevmscan.io/address/0xb85a8fda7f5e52e32fa5582847cfffee9456a5dc) |
| Stable | [`0x938Ca0dbaF2876011CD43598b14acA21a6c61b6e`](https://stablescan.xyz/address/0x938Ca0dbaF2876011CD43598b14acA21a6c61b6e) | [`0xA27eCe4f3108655dCE7d8aD684B780a2163928A1`](https://stablescan.xyz/address/0xA27eCe4f3108655dCE7d8aD684B780a2163928A1) |
| Monad | [`0x40f66fff44dbbee88058185f2cfe287558d7e532`](https://monadscan.com/address/0x40f66fff44dbbee88058185f2cfe287558d7e532) | [`0x92e6892706053ee85fc1178affcb3803118d2c4f`](https://monadscan.com/address/0x92e6892706053ee85fc1178affcb3803118d2c4f) |
| Somnia | n/a | [`0xE9e53734D2b67Ae263089d7a5dE1F5d97ab8cBDD`](https://explorer.somnia.network/address/0xE9e53734D2b67Ae263089d7a5dE1F5d97ab8cBDD) |
| Robinhood | n/a | [`0xEfb78823eDCB57d78975a33576A7361dBD154d64`](https://robinhoodchain.blockscout.com/address/0xEfb78823eDCB57d78975a33576A7361dBD154d64) |
| Tempo | n/a | [`0xD512291495ADDBcEC271b5FF802868F5d2f7f83F`](https://explore.tempo.xyz/address/0xD512291495ADDBcEC271b5FF802868F5d2f7f83F) (`RemoteMintRedeemHopTempo`, TIP20 fees — see [MintRedeemHop on Tempo](#mintredeemhop-on-tempo)) |

### Testnet
| Chain | `RemoteHop` |
| --- | --- |
| Fraxtal | [`0xd593Df4E2E3156C5707bB6AE4ba26fd4A9A04586`](https://holesky.fraxscan.com/address/0xd593Df4E2E3156C5707bB6AE4ba26fd4A9A04586) |
| Eth Sepolia | [`0xa46A266dCBf199a71532c76967e200994C5A0D6d`](https://sepolia.etherscan.io/address/0xa46A266dCBf199a71532c76967e200994C5A0D6d) |
| Arb Sepolia | [`0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A`](https://sepolia.arbiscan.io/address/0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A) |