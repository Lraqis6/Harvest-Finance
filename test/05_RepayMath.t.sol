// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "forge-std/Test.sol";
import {FlashFee} from "../src/libraries/FlashFee.sol";

/// @title 测试 5：还款精度（ceil(amount*1000/997)）
contract RepayMathTest is Test {
    function test_OwedIsCeilOf1000Over997() public {
        assertEq(FlashFee.owed(1_000_000e6), 1_003_009_027_081 + 1); // 期望上取整
    }

    function test_OwedAlwaysNotLessThanReference() public {
        for (uint256 i = 1; i < 50; i++) {
            uint256 amount = i * 1e18 + 7;
            uint256 ref = FlashFee.ceilDiv(amount * 1000, 997);
            assertGe(FlashFee.owed(amount), ref);
            assertLe(FlashFee.owed(amount) - ref, 1, "at most 1 wei extra");
        }
    }

    function test_RoundingDownWouldUnderpay() public {
        uint256 amount = 123_456_789;
        uint256 floorPay = (amount * 1000) / 997;
        assertGt(FlashFee.owed(amount), floorPay, "floor rounding underpays and fails the k check");
    }
}
