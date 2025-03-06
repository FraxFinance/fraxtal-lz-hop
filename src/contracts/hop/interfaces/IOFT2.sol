// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOFT2 {
    function combineOptions(
        uint32 _eid,
        uint16 _msgType,
        bytes calldata _extraOptions
    ) external view returns (bytes memory);
}