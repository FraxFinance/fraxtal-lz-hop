// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract FraxtalConstants {
    error InvalidOApp();

    /// @dev from FraxtalL2.sol
    address public constant frax = 0xFc00000000000000000000000000000000000001;
    address public constant sFrax = 0xfc00000000000000000000000000000000000008;
    address public constant sFrxEth = 0xFC00000000000000000000000000000000000005;
    address public constant fxs = 0xFc00000000000000000000000000000000000002;
    address public constant fpi = 0xFc00000000000000000000000000000000000003;

    // Note: each curve pool is "native" token / "layerzero" token with "a" factor of 1400
    // All OFTs can be referenced at https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#proxy-upgradeable-ofts
    address public constant fraxOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public constant sFraxOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public constant sFrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address public constant fxsOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address public constant fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    address public constant fraxCurve = 0x53f8F4e154F68C2D29a0D06BD50f82bCf1bd95dB;
    address public constant sFraxCurve = 0xd2866eF5A94E741Ec8EDE5FF8e3A1f9C59c5e298;
    address public constant sFrxEthCurve = 0xe5F61df936d50302962d5B914537Ff3cB63b3526;
    address public constant fxsCurve = 0xBc383485068Ffd275D7262Bef65005eE7a5A1870;
    address public constant fpiCurve = 0x7FaA69f8fEbe38bBfFbAE3252DE7D1491F0c6157;

    /// @dev Using the _oApp address (as provided by the endpoint), return the respective tokens
    /// @dev ie. a send of FRAX would have the _oApp address of the FRAX OFT
    /// @return nToken "Native token" (pre-compiled proxy address)
    /// @return curve (Address of curve.fi pool for nToken/lzToken)
    function _getRespectiveTokens(address _oApp) internal pure returns (address nToken, address curve) {
        if (_oApp == fraxOft) {
            nToken = frax;
            curve = fraxCurve;
        } else if (_oApp == sFraxOft) {
            nToken = sFrax;
            curve = sFraxCurve;
        } else if (_oApp == sFrxEthOft) {
            nToken = sFrxEth;
            curve = sFrxEthCurve;
        } else if (_oApp == fxsOft) {
            nToken = fxs;
            curve = fxsCurve;
        } else if (_oApp == fpiOft) {
            nToken = fpi;
            curve = fpiCurve;
        } else {
            revert InvalidOApp();
        }
    }
}
