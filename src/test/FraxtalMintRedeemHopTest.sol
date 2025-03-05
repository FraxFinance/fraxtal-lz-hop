// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BaseTest.t.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { FraxtalMintRedeemHop } from "../contracts/composers/FraxtalMintRedeemHop.sol";

contract FraxtalMintRedeemHopTest is BaseTest {
    FraxtalMintRedeemHop hop;
    function setUp() public virtual {
        vm.createSelectFork(vm.envString("FRAXTAL_MAINNET_URL"), 17180177);
        hop = new FraxtalMintRedeemHop(2800E18);
    }

    address CAC = 0x103C430c9Fcaa863EA90386e3d0d5cd53333876e;
    address EXECUTOR = 0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d;
    address DVN = 0xcCE466a522984415bC91338c232d98869193D46e;
    address TREASURY = 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821;

    function quote(string memory chain, uint32 eid) public {
        MessagingFee memory fee = hop.quote(eid, bytes32(uint256(uint160(address(this)))), 100E18, 100E18);
        console.log(chain, fee.nativeFee, fee.lzTokenFee, quoteDirectly(eid));
    }

    function test_quote() public {
        quote("Ethereum", 30101);
        quote("Arbitrum", 30110);
        quote("Optimism", 30111);
    }

    function test_quoteSelf() public {
        MessagingFee memory fee = quote(30255, bytes32(uint256(uint160(address(this)))), 100E18, 100E18);
        console.log(fee.nativeFee, fee.lzTokenFee);
        uint256 quoteDirectlyFee = quoteDirectly(30255);
        console.log(quoteDirectlyFee);
    }

    function test_quoteDirectly() public {
        console.log("Abstract",quoteDirectly(30324));
        console.log("Ape",quoteDirectly(30312));
        console.log("Aptos",quoteDirectly(30108));
        console.log("Astar",quoteDirectly(30210));
        console.log("Avalange",quoteDirectly(30106));
        console.log("Etherlink",quoteDirectly(30292));
        console.log("Solana",quoteDirectly(30168));
        
    }

    function quoteDirectly(uint32 _dstEid) public returns (uint256 finalFee) {
        bytes memory options = IOFT2(CAC).combineOptions(_dstEid, 1, OptionsBuilder.newOptions());
        uint256 dvnFee = ILayerZeroDVN(DVN).getFee(_dstEid, 5, address(this), "");
        options = hex"0100110100000000000000000000000000030d40";
        uint256 executorFee = IExecutor(EXECUTOR).getFee(_dstEid, address(this), 40, options);
        uint256 totalFee = dvnFee * 2 + executorFee;
        uint256 treasuryFee = ILayerZeroTreasury(TREASURY).getFee(address(this), _dstEid, totalFee, false);
        finalFee = totalFee + treasuryFee;
    }

    function quote(uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD) public view returns (MessagingFee memory fee) {
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _minAmountLD
        });
        fee = IOFT(CAC).quoteSend(sendParam, false);
    }

    function _generateSendParam(
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) internal pure returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        sendParam.dstEid = _dstEid;
        sendParam.to = _to;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        sendParam.extraOptions = options;
    }    
}

interface IExecutor {
    // @notice query the executor price for relaying the payload and its proof to the destination chain
    // @param _dstEid - the destination endpoint identifier
    // @param _sender - the source sending contract address. executors may apply price discrimination to senders
    // @param _calldataSize - dynamic data size of message + caller params
    // @param _options - optional parameters for extra service plugins, e.g. sending dust tokens at the destination chain
    function getFee(
        uint32 _dstEid,
        address _sender,
        uint256 _calldataSize,
        bytes calldata _options
    ) external view returns (uint256 price);
}

interface ILayerZeroTreasury {
    function getFee(
        address _sender,
        uint32 _dstEid,
        uint256 _totalNativeFee,
        bool _payInLzToken
    ) external view returns (uint256 fee);
}

interface ILayerZeroDVN {
    // @notice query the dvn fee for relaying block information to the destination chain
    // @param _dstEid the destination endpoint identifier
    // @param _confirmations - block confirmation delay before relaying blocks
    // @param _sender - the source sending contract address
    // @param _options - options
    function getFee(
        uint32 _dstEid,
        uint64 _confirmations,
        address _sender,
        bytes calldata _options
    ) external view returns (uint256 fee);
}

interface IOFT2 {
    function combineOptions(
        uint32 _eid,
        uint16 _msgType,
        bytes calldata _extraOptions
    ) external view returns (bytes memory);
}