// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

/// @title Uniswap V2 闪电兑换手续费
/// @notice 闪电兑换（flash swap）需要在回调里补回 amount * 1000 / 997 以上，
///         不足会被 pair 的 k 校验拒绝（"UniswapV2: K"）。向上取整是为了避免 1 wei 边界。
library FlashFee {
    /// @notice 应补回的数量：ceil(amount * 1000 / 997)
    function owed(uint256 amount) internal pure returns (uint256) {
        return (amount * 1000) / 997 + 1;
    }

    /// @notice 参考实现（向上取整的通用形式），用于测试对照
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }
}
