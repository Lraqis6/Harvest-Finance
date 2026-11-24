// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

/// @title Curve yPool 最小接口
/// @dev 关键点：yPool 里存的是 yToken，因此底层币兑换必须用 exchange_underlying，
///      币序查询函数是 coins(int128) 而不是 coins(uint256)。
interface ICurveYPoolLike {
    function coins(int128 i) external view returns (address);
    function A() external view returns (uint256);
    function fee() external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);
    /// @dev 注意：2020 年的 yPool 版本 exchange_underlying 没有返回值（实测 returndata 为 0 字节），
    ///      如果按 returns (uint256) 声明，解码空返回数据会直接 revert。
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 minDy) external;
}
