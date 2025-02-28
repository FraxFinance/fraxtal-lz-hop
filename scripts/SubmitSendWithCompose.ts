import * as dotenv from "dotenv";
import { ethers } from "ethers";
import { Options } from '@layerzerolabs/lz-v2-utilities'
import abi from "./OFT-abi.json";

dotenv.config();
const PK: string = process.env.PK!;

const fraxtalMintRedeemHop = "0x"; // TODO

const sourceRpc = 'https://mainnet.base.org';
const fraxtalRpc = 'https://rpc.frax.com';

const dstEid = 30332; // sonic

const frxUsdOft = "0x80Eede496655FB9047dd39d9f418d5483ED600df";
const sfrxUsdOft = '0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0';


async function main() {
    const provider = new ethers.providers.JsonRpcProvider(sourceRpc);
    const signer = new ethers.Wallet(PK, provider);
    const contract = new ethers.Contract(frxUsdOft, abi, signer);

    // basic send
    // https://layerzeroscan.com/tx/0x227f96abde1c4a93514f8cc663e30cbed1ecb6d1d4008c7cdbf0f3de0261eb40
    // const to = ethers.utils.zeroPad(signer.address, 32);
    // const options = Options.newOptions().toHex().toString();
    // composeMsg = '0x';

    // Send with Mint Redeem Hop
    const to = ethers.utils.zeroPad(fraxtalMintRedeemHop, 32);
    const options = Options.newOptions().addExecutorComposeOption(0, 200_000, 0).toHex().toString();
    const amount = 20 * 10**18;
    const abiCoder = new ethers.utils.AbiCoder();
    const recipient = ethers.utils.zeroPad(signer.address, 32);
    const minAmountLD = 0;
    const composeMsg = abiCoder.encode(["bytes32", "uint32"], [recipient, dstEid]);

    const sendParam = [
        30255,
        to,
        amount.toString(),
        minAmountLD.toString(),
        options,
        composeMsg,
        '0x'
    ]

    // get native fee
    const [nativeFee] = await contract.quoteSend(sendParam, false);

    // execute the send
    await contract.send(sendParam, [nativeFee, 0], signer.address, { value: nativeFee });
}

main();
