pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHopV2 } from "src/contracts/hop/RemoteHopV2.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IExecutor {
    function endpoint() external view returns (address);
    function localEidV2() external view returns (uint32);
}

interface ISendLibrary {
    function treasury() external view returns (address);
    function version() external view returns (uint64, uint8, uint8);
}

interface IDVN {
    function vid() external view returns (uint32);
}

abstract contract DeployRemoteHopV2 is BaseScript {
    address constant FRAXTAL_HOP = 0x546FbA85314f633eEE84cfEe249dE535D82ae252;

    address EXECUTOR;
    address DVN;
    address SEND_LIBRARY;

    address frxUsdOft;
    address sfrxUsdOft;
    address frxEthOft;
    address sfrxEthOft;
    address wFraxOft;
    address fpiOft;
    address[] approvedOfts;

    function run() public broadcaster {
        _validateAddrs();

        approvedOfts.push(frxUsdOft);
        approvedOfts.push(sfrxUsdOft);
        approvedOfts.push(frxEthOft);
        approvedOfts.push(sfrxEthOft);
        approvedOfts.push(wFraxOft);
        approvedOfts.push(fpiOft);

        RemoteHopV2 remoteHop = new RemoteHopV2({
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_HOP))),
            _numDVNs: 3,
            _ENDPOINT: IExecutor(EXECUTOR).endpoint(),
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: ISendLibrary(SEND_LIBRARY).treasury(),
            _EID: IExecutor(EXECUTOR).localEidV2(),
            _approvedOfts: approvedOfts
        });
        console.log("RemoteHop deployed at:", address(remoteHop));
    }

    function _validateAddrs() internal view returns (bool) {
        (uint64 major, uint8 minor, uint8 endpointVersion) = ISendLibrary(SEND_LIBRARY).version();
        require(major == 3 && minor == 0 && endpointVersion == 2, "Invalid SendLibrary version");

        require(IExecutor(EXECUTOR).endpoint() != address(0), "Invalid executor endpoint");
        require(IExecutor(EXECUTOR).localEidV2() != 0, "Invalid executor localEidV2");
        require(IDVN(DVN).vid() != 0, "Invalid DVN vid");

        require(isStringEqual(IERC20Metadata(frxUsdOft).symbol(), "frxUSD"), "frxUsdOft != frxUSD");
        require(isStringEqual(IERC20Metadata(sfrxUsdOft).symbol(), "sfrxUSD"), "sfrxUsdOft != sfrxUSD");
        require(isStringEqual(IERC20Metadata(frxEthOft).symbol(), "frxETH"), "frxEthOft != frxETH");
        require(isStringEqual(IERC20Metadata(sfrxEthOft).symbol(), "sfrxETH"), "sfrxEthOft != sfrxETH");
        require(isStringEqual(IERC20Metadata(wFraxOft).symbol(), "WFRAX"), "wFraxOft != WFRAX");
        require(isStringEqual(IERC20Metadata(fpiOft).symbol(), "FPI"), "fpiOft != FPI");
    }

    function isStringEqual(string memory _a, string memory _b) public pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }
}