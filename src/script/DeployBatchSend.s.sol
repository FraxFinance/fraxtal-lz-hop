// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { BatchSend } from "src/contracts/batch/BatchSend.sol";

contract DeployBatchSend is BaseScript {
    function run() public broadcaster {
        BatchSend batchSend = new BatchSend();
    }
}
