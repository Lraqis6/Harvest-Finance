// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

/// @title Uniswap V2 Pair 最小接口（闪电兑换只需要 swap / token0 / token1 / getReserves）
interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
