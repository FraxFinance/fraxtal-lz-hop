// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { IHopRegistry } from "./IHopRegistry.sol";

interface IHopApp {
   function initializeHopApp(address registry, uint32 _appEid, uint96 _appNo) external;
}