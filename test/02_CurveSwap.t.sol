// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ForkBase.sol";
import {Mainnet} from "../src/Addresses.sol";
import {IHarvestVaultLike} from "../src/interfaces/IHarvestVaultLike.sol";
import {ICurveYPoolLike} from "../src/interfaces/ICurveYPoolLike.sol";
import {IERC20Like} from "../src/interfaces/IERC20Like.sol";

/// @title 测试 2：单次 Curve 兑换 —— 观察份额价位移方向与幅度（必须 < 3%）
contract CurveSwapTest is ForkBase {
    function setUp() public {
        _fork();
    }

    function test_SingleSwapPushesSharePriceDownUnder3Percent() public {
        if (!forked) return;

        uint256 ppfsBefore = IHarvestVaultLike(Mainnet.FUSDC).getPricePerFullShare();
        uint256 vpBefore = ICurveYPoolLike(Mainnet.YPOOL).get_virtual_price();

        uint256 amount = Mainnet.TILT_USDT;
        deal(Mainnet.USDT, address(this), amount);
        IERC20Like(Mainnet.USDT).approve(Mainnet.YPOOL, amount);

        uint256 usdcBefore = IERC20Like(Mainnet.USDC).balanceOf(address(this));
        ICurveYPoolLike(Mainnet.YPOOL).exchange_underlying(2, 1, amount, 0);
        uint256 got = IERC20Like(Mainnet.USDC).balanceOf(address(this)) - usdcBefore;

        uint256 ppfsAfter = IHarvestVaultLike(Mainnet.FUSDC).getPricePerFullShare();
        uint256 vpAfter = ICurveYPoolLike(Mainnet.YPOOL).get_virtual_price();

        emit log_named_decimal_uint("swap out USDC", got, 6);
        emit log_named_decimal_uint("ppfs before", ppfsBefore, 6);
        emit log_named_decimal_uint("ppfs after", ppfsAfter, 6);
        emit log_named_decimal_uint("virtual price before", vpBefore, 18);
        emit log_named_decimal_uint("virtual price after", vpAfter, 18);

        assertGt(got, (amount * 99) / 100, "swap roughly 1:1");
        assertLt(ppfsAfter, ppfsBefore, "share price must drop");
        uint256 drop = ((ppfsBefore - ppfsAfter) * 10_000) / ppfsBefore;
        assertLt(drop, 300, "displacement < 3% arb threshold");
    }
}
