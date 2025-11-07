pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";

/// @notice Set RemoteHop params via Fraxtal
contract HopSetter is OwnableUpgradeable {
    IHopV2 public fraxtalHop;
    address public frxUsdOft;
    uint256 public localEid;

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(address _fraxtalHop, address _frxUsdOft) external initializer {
        __Ownable_init();

        fraxtalHop = IHopV2(_fraxtalHop);
        frxUsdOft = _frxUsdOft;
        localEid = fraxtalHop.localEid();
    }

    function recoverETH(uint256 value, address to) external onlyOwner {
        (bool success, ) = to.call{ value: value }("");
        require(success, "recoverETH failed");
    }

    function callRemoteHops(uint32[] memory eids, uint128 _dstGas, bytes memory _data) external onlyOwner {
        for (uint256 i = 0; i < eids.length; i++) {
            uint32 eid = eids[i];
            bytes32 remoteHop = eid == localEid
                ? bytes32(uint256(uint160(address(fraxtalHop))))
                : fraxtalHop.remoteHop(eid);

            uint256 fee = fraxtalHop.quote({
                _oft: frxUsdOft,
                _dstEid: eid,
                _recipient: remoteHop,
                _amountLD: 0,
                _dstGas: _dstGas,
                _data: _data
            });

            fraxtalHop.sendOFT{ value: fee }({
                _oft: frxUsdOft,
                _dstEid: eid,
                _recipient: remoteHop,
                _amountLD: 0,
                _dstGas: _dstGas,
                _data: _data
            });
        }
    }
}
