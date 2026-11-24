// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ForkBase.sol";
import {Mainnet} from "../src/Addresses.sol";
import {FlashLoanProbe} from "../src/mocks/FlashLoanProbe.sol";
import {FlashFee} from "../src/libraries/FlashFee.sol";

/// @title 测试 1：纯闪电贷借还（验证回调签名与 0.3% 手续费公式）
contract FlashLoanTest is ForkBase {
    FlashLoanProbe internal probe;

    function setUp() public {
        _fork();
        if (forked) probe = new FlashLoanProbe(Mainnet.UNI_USDT_WETH, Mainnet.USDT);
    }

    function test_BorrowThenRepay() public {
        if (!forked) return;
        uint256 amount = 1_000_000e6;
        probe.run(amount, 0);
        assertEq(probe.borrowed(), amount);
        assertEq(probe.repaid(), FlashFee.owed(amount));
        assertGt(probe.repaid(), amount, "fee > 0");
    }

    function test_UnderpayOneWeiReverts() public {
        if (!forked) return;
        vm.expectRevert(bytes("UniswapV2: K"));
        probe.run(1_000_000e6, 1);
    }
}
