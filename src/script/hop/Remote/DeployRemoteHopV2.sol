pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHopV2 } from "src/contracts/hop/RemoteHopV2.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { FraxUpgradeableProxy } from "frax-std/FraxUpgradeableProxy.sol";

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

interface IOFT {
    function token() external view returns (address);
}

abstract contract DeployRemoteHopV2 is BaseScript {
    address constant FRAXTAL_HOP = 0xC87D7e85aFCc8D51056D8B2dB95a89045BbE60DC;
    address constant HOP_SETTER = 0x24fe43E1667e8d139c61568C9bAf75EfBaE13502;

    address proxyAdmin;
    address endpoint;
    uint32 localEid;

    address EXECUTOR;
    address DVN;
    address SEND_LIBRARY;

    address msig;
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

        address remoteHop = deployRemoteHopV2({
            _proxyAdmin: proxyAdmin,
            _localEid: localEid,
            _endpoint: endpoint,
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_HOP))),
            _hopSetter: HOP_SETTER,
            _msig: msig,
            _numDVNs: 3,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: ISendLibrary(SEND_LIBRARY).treasury(),
            _approvedOfts: approvedOfts
        });

        // revoke deployer admin role
        RemoteHopV2(payable(remoteHop)).renounceRole(bytes32(0), vm.addr(privateKey));

        console.log("RemoteHop deployed at:", remoteHop);
    }

    function _validateAddrs() internal view {
        (uint64 major, uint8 minor, uint8 endpointVersion) = ISendLibrary(SEND_LIBRARY).version();
        require(major == 3 && minor == 0 && endpointVersion == 2, "Invalid SendLibrary version");

        require(IExecutor(EXECUTOR).endpoint() == endpoint, "Invalid executor endpoint");
        require(IExecutor(EXECUTOR).localEidV2() == localEid, "Invalid executor localEidV2");
        require(IDVN(DVN).vid() != 0, "Invalid DVN vid");

        require(isStringEqual(IERC20Metadata(IOFT(frxUsdOft).token()).symbol(), "frxUSD"), "frxUsdOft != frxUSD");
        require(isStringEqual(IERC20Metadata(IOFT(sfrxUsdOft).token()).symbol(), "sfrxUSD"), "sfrxUsdOft != sfrxUSD");
        require(isStringEqual(IERC20Metadata(IOFT(frxEthOft).token()).symbol(), "frxETH"), "frxEthOft != frxETH");
        require(isStringEqual(IERC20Metadata(IOFT(sfrxEthOft).token()).symbol(), "sfrxETH"), "sfrxEthOft != sfrxETH");
        require(isStringEqual(IERC20Metadata(IOFT(wFraxOft).token()).symbol(), "WFRAX"), "wFraxOft != WFRAX");
        require(isStringEqual(IERC20Metadata(IOFT(fpiOft).token()).symbol(), "FPI"), "fpiOft != FPI");
    }

    function isStringEqual(string memory _a, string memory _b) public pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }
}

function deployRemoteHopV2(
    address _proxyAdmin,
    uint32 _localEid,
    address _endpoint,
    bytes32 _fraxtalHop,
    address _hopSetter,
    address _msig,
    uint32 _numDVNs,
    address _EXECUTOR,
    address _DVN,
    address _TREASURY,
    address[] memory _approvedOfts
) returns (address payable) {
    bytes memory initializeArgs = abi.encodeCall(
        RemoteHopV2.initialize,
        (_localEid, _endpoint, _fraxtalHop, _numDVNs, _EXECUTOR, _DVN, _TREASURY, _approvedOfts)
    );

    address implementation = address(new RemoteHopV2());
    FraxUpgradeableProxy proxy = new FraxUpgradeableProxy(implementation, _proxyAdmin, initializeArgs);

    // add HopSetter/msig as admin
    RemoteHopV2(payable(address(proxy))).grantRole(bytes32(0), _hopSetter);
    RemoteHopV2(payable(address(proxy))).grantRole(bytes32(0), _msig);

    // set solana enforced options
    RemoteHopV2(payable(address(proxy))).setExecutorOptions(
        30168,
        hex"0100210100000000000000000000000000030D40000000000000000000000000002DC6C0"
    );

    return payable(address(proxy));
}
