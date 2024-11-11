// SPDC-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICurve {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
    function get_balances() external view returns (uint256[] memory);
}
