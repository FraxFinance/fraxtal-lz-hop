// SPDC-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IWETH {
    function withdraw(uint256 wad) external;
    function deposit() external payable;
}
