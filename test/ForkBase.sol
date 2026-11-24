// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "forge-std/Test.sol";
import {Mainnet} from "../src/Addresses.sol";

/// @notice 所有 fork 测试的公共基类：没有配置 RPC 时自动跳过，而不是报错
abstract contract ForkBase is Test {
    string internal rpcUrl;
    bool internal forked;

    function _fork() internal {
        rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpcUrl, Mainnet.FORK_BLOCK);
        forked = true;
    }
}
