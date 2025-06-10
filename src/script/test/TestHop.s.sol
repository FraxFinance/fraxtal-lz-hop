pragma solidity ^0.8.0;

import { BaseScript } from "frax-std/BaseScript.sol";

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
    function quote(
        address oft,
        uint32 dstEid,
        bytes32 toAsBytes32,
        uint256 amount
    ) external view returns (MessagingFee memory fee);
    function sendOFT(address oft, uint32 dstEid, bytes32 toAsBytes23, uint256 amount) external payable;
}
interface IMintRedeemHop {
    function quote(address oft, bytes32 toAsBytes32, uint256 amount) external view returns (MessagingFee memory fee);
    function mintRedeem(address oft, uint256 amount) external payable;
}

// forge script src/script/test/TestHop.s.sol --rpc-url https://eth-sepolia.public.blastapi.io --broadcast --evm-version shanghai
contract TestHop is BaseScript {
    uint256 public configDeployerPK = vm.envUint("PK_CONFIG_DEPLOYER");

    function run() public {
        // Eth sepolia frxUSD => (fraxtal) => Arb sepolia frxUSD OFT

        address oft = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2; // frxUSD OFT on Eth Sepolia
        address remoteHop = 0xa46A266dCBf199a71532c76967e200994C5A0D6d; // See deployed contracts below
        uint256 amount = 10_000e18;
        uint32 dstEid = 40255; // testnet fraxtal
        bytes32 to = bytes32(uint256(uint160(vm.addr(configDeployerPK)))); // example

        // 1. Quote cost of send
        MessagingFee memory fee = IRemoteHop(remoteHop).quote(oft, dstEid, to, amount);

        // 2. Approve OFT underlying token to be transferred to the remoteHop
        vm.startBroadcast(configDeployerPK);
        IERC20(IOFT(oft).token()).approve(remoteHop, amount);

        // 3. Send the OFT to destination
        IRemoteHop(remoteHop).sendOFT{ value: fee.nativeFee }(oft, dstEid, to, amount);
    }
}
