//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FraxProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address initialOwner,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, initialOwner, _data) {}

    receive() external payable {}
}
