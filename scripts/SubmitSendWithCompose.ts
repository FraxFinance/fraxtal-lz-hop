import * as dotenv from "dotenv";
import { ethers } from "ethers";
import { Options } from '@layerzerolabs/lz-v2-utilities'
import abi from "./OFT-abi.json";

dotenv.config();
const PK: string = process.env.PK!;

const receiverProxy = "0xF7c1a390f77B294c107Ca4204BffdC1a9Fae72F9"; // fraxtal MockReceiver
const oft = "0x909DBdE1eBE906Af95660033e478D59EFe831fED"; // frax

async function main() {
    const url = 'https://mainnet.base.org';
    const provider = new ethers.providers.JsonRpcProvider(url);
    const signer = new ethers.Wallet(PK, provider);
    const contract = new ethers.Contract(oft, abi, signer);

    // basic send
    // https://layerzeroscan.com/tx/0x227f96abde1c4a93514f8cc663e30cbed1ecb6d1d4008c7cdbf0f3de0261eb40
    // const to = ethers.utils.zeroPad(signer.address, 32);
    // const options = Options.newOptions().toHex().toString();
    // composeMsg = '0x';

    // Send with atomic curve swap
    // https://layerzeroscan.com/tx/0xab618d33c30660b28a623e821775ee71b34f2d597181c6cfb5966c849c112676
    const to = ethers.utils.zeroPad(receiverProxy, 32);
    const options = Options.newOptions().addExecutorComposeOption(0, 1_000_000, 0).toHex().toString();
    const amount = 10**13;
    const abiCoder = new ethers.utils.AbiCoder();
    const recipient = signer.address;
    const minAmountOut = 0;
    const minAmountLD = 0;
    const composeMsg = abiCoder.encode(["address", "uint256"], [recipient, minAmountOut]);

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
