// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ForkBase.sol";
import {Mainnet} from "../src/Addresses.sol";
import {ManipulationGuard} from "../src/defense/ManipulationGuard.sol";
import {IHarvestVaultLike} from "../src/interfaces/IHarvestVaultLike.sol";
import {ICurveYPoolLike} from "../src/interfaces/ICurveYPoolLike.sol";
import {IERC20Like} from "../src/interfaces/IERC20Like.sol";

/// @title 测试 7：防护组件 —— 用时间加权均价 + 偏差阈值挡住同交易内的价格操纵
contract DefenseTest is ForkBase {
    ManipulationGuard internal guard;

    function setUp() public {
        _fork();
        if (forked) guard = new ManipulationGuard(50, 3600); // 0.5% 偏差上限
    }

    function test_GuardRejectsFlashLoanManipulation() public {
        if (!forked) return;

        uint256 ppfsBefore = IHarvestVaultLike(Mainnet.FUSDC).getPricePerFullShare();
        guard.poke(ppfsBefore, block.timestamp);

        // 模拟攻击者的砸盘（同一区块内完成）
        deal(Mainnet.USDT, address(this), Mainnet.TILT_USDT);
        IERC20Like(Mainnet.USDT).approve(Mainnet.YPOOL, Mainnet.TILT_USDT);
        ICurveYPoolLike(Mainnet.YPOOL).exchange_underlying(2, 1, Mainnet.TILT_USDT, 0);

        uint256 ppfsAfter = IHarvestVaultLike(Mainnet.FUSDC).getPricePerFullShare();
        assertLt(ppfsAfter, ppfsBefore);

        vm.expectRevert();
        guard.check(ppfsAfter); // 偏差约 0.89% > 0.5%，被拦下
    }

    function test_GuardAllowsNormalFluctuation() public {
        if (!forked) return;
        uint256 ppfs = IHarvestVaultLike(Mainnet.FUSDC).getPricePerFullShare();
        guard.poke(ppfs, block.timestamp);
        guard.check(ppfs - ppfs / 1000); // 0.1% 的正常波动放行
    }
}
