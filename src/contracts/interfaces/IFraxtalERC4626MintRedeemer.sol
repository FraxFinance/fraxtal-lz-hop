// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFraxtalERC4626MintRedeemer {
    function deposit(uint256 _assetsIn, address _receiver) external returns (uint256 _sharesOut);
    function redeem(uint256 _sharesIn, address _receiver, address _owner) external returns (uint256 _assetsOut);
    function pricePerShare() external view returns (uint256);
}