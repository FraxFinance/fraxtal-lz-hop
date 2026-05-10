// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

struct LegacyHopTarget {
    string name;
    address remoteHop;
    address mintRedeemHop;
    bool exists;
}

contract HopConstants {
    mapping(uint256 chainId => LegacyHopTarget target) internal legacyHopTargets;

    constructor() {
        _addLegacyHopTarget(
            1,
            "Ethereum",
            0x3ad4dC2319394bB4BE99A0e4aE2AbF7bCEbD648E,
            0x99B5587ab54A49e3F827D10175Caf69C0187bfA8
        );
        _addLegacyHopTarget(
            10,
            "Optimism",
            0x31D982ebd82Ad900358984bd049207A4c2468640,
            0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A
        );
        _addLegacyHopTarget(
            56,
            "BSC",
            0x452420df4AC1e3db5429b5FD629f3047482C543C,
            0xdee45510b42Cb0678C8A61D043C698aF66b0d852
        );
        _addLegacyHopTarget(
            130,
            "Unichain",
            0xc71BF5Ee4740405030eF521F18A96eA14fec802D,
            0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263
        );
        _addLegacyHopTarget(
            137,
            "Polygon",
            0xf74D38A26948E9DDa53eD85cF03C6b1188FbB30C,
            0x5658e82E330e094627D9b362ed0E137eA06673C4
        );
        _addLegacyHopTarget(
            143,
            "Monad",
            0x40F66FFf44DBBee88058185F2cFE287558D7E532,
            0x92E6892706053ee85fC1178AFFCB3803118D2C4F
        );
        _addLegacyHopTarget(
            146,
            "Sonic",
            0x3A5cDA3Ac66Aa80573402610c94B74eD6cdb2F23,
            0xf6115Bb9b6A4b3660dA409cB7afF1fb773efaD0b
        );
        _addLegacyHopTarget(
            196,
            "X-Layer",
            0x79152c303AD5aE429eDefa4553CB1Ad2c6EE1396,
            0x45c6852A5188Ce1905567EA83454329bd4982007
        );
        _addLegacyHopTarget(
            324,
            "ZkSync",
            0xc5e4A0cfef8D801278927C25fB51C1DB7b69dDFb,
            0xa05E9F9B97c963B5651ed6A50Fae46625a8C400b
        );
        _addLegacyHopTarget(
            480,
            "Worldchain",
            0x938d99A81814f66b01010d19DDce92A633441699,
            0x111ddab65Af5fF96b674400246699ED40F550De1
        );
        _addLegacyHopTarget(
            988,
            "Stable",
            0x938Ca0dbaF2876011CD43598b14acA21a6c61b6e,
            0xA27eCe4f3108655dCE7d8aD684B780a2163928A1
        );
        _addLegacyHopTarget(
            999,
            "Hyperliquid",
            0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2,
            0xb85A8FDa7F5e52E32fa5582847CFfFee9456a5Dc
        );
        _addLegacyHopTarget(
            1101,
            "PolygonZkEvm",
            0x111ddab65Af5fF96b674400246699ED40F550De1,
            0xc71BF5Ee4740405030eF521F18A96eA14fec802D
        );
        _addLegacyHopTarget(
            1329,
            "Sei",
            0x3a6F28e8DDD232B02C72C491Bd1626F69D2fb329,
            0x0255a172d0a060F2bEab3e7c12334dD73cCC26ba
        );
        _addLegacyHopTarget(
            2741,
            "Abstract",
            0xc5e4A0cfef8D801278927C25fB51C1DB7b69dDFb,
            0xa05E9F9B97c963B5651ed6A50Fae46625a8C400b
        );
        _addLegacyHopTarget(
            8453,
            "Base",
            0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45,
            0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE
        );
        _addLegacyHopTarget(
            34443,
            "Mode",
            0x486CB4788F1bE7cdEf9301a7a637B451df3Cf262,
            0x7360575f6f8F91b38dD078241b0Df508f5fBfDf9
        );
        _addLegacyHopTarget(
            42161,
            "Arbitrum",
            0x29F5DBD0FE72d8f11271FCBE79Cb87E18a83C70A,
            0xa46A266dCBf199a71532c76967e200994C5A0D6d
        );
        _addLegacyHopTarget(
            43114,
            "Avalanche",
            0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A,
            0x452420df4AC1e3db5429b5FD629f3047482C543C
        );
        _addLegacyHopTarget(
            57073,
            "Ink",
            0x7a07D606c87b7251c2953A30Fa445d8c5F856C7A,
            0x452420df4AC1e3db5429b5FD629f3047482C543C
        );
        _addLegacyHopTarget(
            59144,
            "Linea",
            0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876,
            0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb
        );
        _addLegacyHopTarget(
            747474,
            "Katana",
            0x5d8EB59A12Bc98708702305A7b032f4b69Dd5b5c,
            0xF6f45CCB5E85D1400067ee66F9e168f83e86124E
        );
        _addLegacyHopTarget(
            80094,
            "Berachain",
            0xc71BF5Ee4740405030eF521F18A96eA14fec802D,
            0x983aF86c94Fe3963989c22CeeEb6eA8Eac32D263
        );
        _addLegacyHopTarget(
            81457,
            "Blast",
            0xe93Cb38f97469eac2f284a87813D0d701b28E58e,
            0x85b1714b25f40FD5025423124c076476073180b3
        );
        _addLegacyHopTarget(
            98866,
            "Plume",
            0x6cA98f43719231d38F6426DB64C7F3D5C7CE7876,
            0xa71f2204EDDB8d84F411A0C712687FAe5002e7Fb
        );
        _addLegacyHopTarget(
            534352,
            "Scroll",
            0xF6f45CCB5E85D1400067ee66F9e168f83e86124E,
            0x91DDB0E0C36B901C6BF53B9Eb5ACa0Eb1465F558
        );
        _addLegacyHopTarget(
            1313161554,
            "Aurora",
            0x53e36C8380Ff62D7964BFa4868A0045E58A52344,
            0x8EbB34b1880B2EA5e458082590B3A2c9Ea7C41A2
        );
    }

    function _legacyHopTargetFor(uint256 chainId) internal view returns (LegacyHopTarget storage target) {
        target = legacyHopTargets[chainId];
        require(target.exists, "missing legacy Hop target");
    }

    function _addLegacyHopTarget(
        uint256 chainId,
        string memory name,
        address remoteHop,
        address mintRedeemHop
    ) internal {
        legacyHopTargets[chainId] = LegacyHopTarget({
            name: name,
            remoteHop: remoteHop,
            mintRedeemHop: mintRedeemHop,
            exists: true
        });
    }
}
