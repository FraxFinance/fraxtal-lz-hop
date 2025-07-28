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

## Deployed Contracts
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

### Testnet
| Chain | `RemoteHop` |
| --- | --- |
| Fraxtal | [`0xd593Df4E2E3156C5707bB6AE4ba26fd4A9A04586`](https://holesky.fraxscan.com/address/0xd593Df4E2E3156C5707bB6AE4ba26fd4A9A04586) |
| Eth Sepolia | [`0xa46A266dCBf199a71532c76967e200994C5A0D6d`](https://sepolia.etherscan.io/address/0xa46A266dCBf199a71532c76967e200994C5A0D6d) |
| Arb Sepolia | [`0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A`](https://sepolia.arbiscan.io/address/0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A) |