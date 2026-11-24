// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

/// @title 最小 ERC20 接口（USDC 6 位精度 / USDT 6 位精度，均返回 uint256）
interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}
