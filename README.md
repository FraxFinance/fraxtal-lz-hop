## Specification
### RemoteHop
**Goal:** User wants to move [(s)frxUSD, (s)frxETH, FXS, FPI] from chain A to chain B via LZ.
1. User sends OFT to RemoteHop on Chain A
   - If `Chain B == Fraxtal`
        1. Chain A RemoteHop sends OFT to recipient on Fraxtal
   - If `Chain B != Fraxtal`
       1. Chain A RemoteHop sends OFT to Fraxtal Remotehop
        2. Fraxtal Remotehop sends OFT to recipient on chain B.

### MintRedeemHop
**Goal:** User wants to convert their frxUSD to sfrxUSD (or vise versa) on chain A at the best provided rate
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
```

### RemoteHop
```Solidity
// Ethereum
address oft = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0; // proxy frxUSD lockbox
address remoteHop = 0x45C55fb1805d8AC7E5Ba0F933cB7D4Da0Dabd365; // See deployed contracts below
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
// Sonic
address oft = 0x80Eede496655FB9047dd39d9f418d5483ED600df; // frxUSD OFT
address mintRedeemHop = 0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396; // see deployed contracts below
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
| Chain | `RemoteHop` | `MintRedeemHop` |
| --- | ---| ---|
| Fraxtal | [`0xEE30e79b54e9a341dcD5621AF1799e2af799b9B0`](https://fraxscan.com/address/0xEE30e79b54e9a341dcD5621AF1799e2af799b9B0) | [`0xf8b29272Db8B482459596C60b37BBF0B8F86E892`](https://fraxscan.com/address/0xf8b29272Db8B482459596C60b37BBF0B8F86E892) |
| Sonic | [`0x3a6F28e8DDD232B02C72C491Bd1626F69D2fb329`](https://sonicscan.org/address/0x3a6F28e8DDD232B02C72C491Bd1626F69D2fb329) | [`0x0255a172d0a060F2bEab3e7c12334dD73cCC26ba`](https://sonicscan.org/address/0x0255a172d0a060F2bEab3e7c12334dD73cCC26ba) |
| Ethereum | [`0xAFB569240E03bb1d09D0e6245Fbea7F480Ec146e`](https://etherscan.io/address/0xAFB569240E03bb1d09D0e6245Fbea7F480Ec146e) | [`0xF421468116CCa4b04385022685599f128D703276`](https://etherscan.io/address/0xF421468116CCa4b04385022685599f128D703276) |
| Sei | [`0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396`](https://seitrace.com/address/0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396?chain=pacific-1) | [`0x45c6852A5188Ce1905567EA83454329bd4982007`](https://seitrace.com/address/0x45c6852A5188Ce1905567EA83454329bd4982007?chain=pacific-1) |
| Linea | [`0x41158EDf6f0bC47Fc169A516be142E429993ed65`](https://lineascan.build/address/0x41158EDf6f0bC47Fc169A516be142E429993ed65) | [`0x6CA2338a21B2fE9dD39040d2fE06AAD861f77F95`](https://lineascan.build/address/0x6CA2338a21B2fE9dD39040d2fE06AAD861f77F95) |
