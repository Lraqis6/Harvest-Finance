// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

/// @title 份额定价操纵防护（时间加权 + 偏差阈值）
/// @notice 漏洞根因是「用同一交易内可被扭曲的瞬时价格给份额定价」。
///         修复思路：
///           1. 定价必须基于一段时间的加权均价（这里用 EMA 近似 TWAP），
///              单笔交易无法改变已经固化的历史观测；
///           2. 存款/赎回前检查瞬时价格相对 EMA 的偏差，超过阈值直接拒绝，
///              把攻击者的「砸盘—存入—复位—赎回」压缩在同一次交易内变得不可行；
///           3. 观测更新有最小间隔，防止在同一区块内被反复刷新。
/// @dev 这是一个可独立部署的"gate"组件，演示修复逻辑，不依赖 Harvest 源码。
contract ManipulationGuard {
    struct Observation {
        uint256 price;      // 份额价（1e18 标度）
        uint256 timestamp;  // 观测时间
    }

    address public immutable operator;
    uint256 public immutable maxDeviationBps; // 允许的瞬时偏差，例如 100 = 1%
    uint256 public immutable minInterval;     // 两次观测的最小间隔（秒）

    Observation public ema;
    bool private seeded;

    event Observed(uint256 price, uint256 timestamp, uint256 ema);
    event Rejected(uint256 price, uint256 ema, uint256 deviationBps);

    error OnlyOperator();
    error DeviationTooLarge(uint256 price, uint256 ema, uint256 deviationBps);
    error TooSoon(uint256 last, uint256 nowTs);

    constructor(uint256 _maxDeviationBps, uint256 _minInterval) {
        operator = msg.sender;
        maxDeviationBps = _maxDeviationBps;
        minInterval = _minInterval;
    }

    /// @notice 用最新价格更新 EMA（指数移动平均，alpha = 1/8）
    function poke(uint256 price, uint256 timestamp) external {
        if (msg.sender != operator) revert OnlyOperator();
        if (seeded && timestamp < ema.timestamp + minInterval) revert TooSoon(ema.timestamp, timestamp);
        if (!seeded) {
            ema = Observation(price, timestamp);
            seeded = true;
        } else {
            // 时间加权：间隔越长，越信任新观测
            uint256 dt = timestamp - ema.timestamp;
            uint256 alpha = dt >= 3600 ? 1e18 : (dt * 1e18) / 3600;
            uint256 next = (price * alpha + ema.price * (1e18 - alpha)) / 1e18;
            ema = Observation(next, timestamp);
        }
        emit Observed(price, timestamp, ema.price);
    }

    /// @notice 存款/赎回前的闸门
    function check(uint256 price) external view {
        if (!seeded) return;
        uint256 diff = price > ema.price ? price - ema.price : ema.price - price;
        uint256 deviationBps = (diff * 10_000) / ema.price;
        if (deviationBps > maxDeviationBps) revert DeviationTooLarge(price, ema.price, deviationBps);
    }
}
