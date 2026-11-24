// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ForkBase.sol";
import {Mainnet} from "../src/Addresses.sol";
import {ArbGateProbe} from "../src/ArbGateProbe.sol";

/// @title 测试 6：3% 套利闸门的边界（Harvest _deposit 里的 require(strategy.depositArbCheck())）
/// @dev 探针的返回值是通过 revert data 带回来的，因此这里用低级 call + abi.decode
contract ArbGateTest is ForkBase {
    ArbGateProbe internal probe;

    function setUp() public {
        _fork();
        if (forked) probe = new ArbGateProbe();
    }

    function _probe(uint256 amount) internal returns (ArbGateProbe.Result memory r) {
        ArbGateProbe.Cfg memory c = ArbGateProbe.Cfg({
            vault: Mainnet.FUSDC,
            tilt: Mainnet.USDT,
            curvePool: Mainnet.YPOOL,
            pairTilt: Mainnet.UNI_USDT_WETH,
            amount: amount,
            idxTilt: 2,
            idxWant: 1
        });
        (bool ok, bytes memory ret) =
            address(probe).call(abi.encodeWithSelector(ArbGateProbe.probe.selector, c));
        assertFalse(ok, "probe returns result via revert");
        r = abi.decode(ret, (ArbGateProbe.Result));
    }

    function test_GateOpenAtRealAttackSize() public {
        if (!forked) return;
        ArbGateProbe.Result memory r = _probe(Mainnet.TILT_USDT);
        emit log_named_uint("gate open", r.gateOpen ? 1 : 0);
        emit log_named_decimal_uint("ppfs before", r.ppfsBefore, 6);
        emit log_named_decimal_uint("ppfs after", r.ppfsAfter, 6);
        assertTrue(r.gateOpen, "gate stays open at real attack size");
        uint256 dropBps = ((r.ppfsBefore - r.ppfsAfter) * 10_000) / r.ppfsBefore;
        assertLt(dropBps, 300, "displacement < 3%");
        assertGt(dropBps, 50, "displacement large enough for profit");
    }

    function test_BiggerDumpMovesPriceMore() public {
        if (!forked) return;
        ArbGateProbe.Result memory small = _probe(5_000_000e6);
        ArbGateProbe.Result memory big = _probe(Mainnet.TILT_USDT);
        assertGt(small.ppfsAfter, big.ppfsAfter, "bigger dump, lower share price");
    }
}
