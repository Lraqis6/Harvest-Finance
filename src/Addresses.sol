// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

/// @title 主网地址与实测常量（全部在归档节点上复核过）
library Mainnet {
    // ---- 交易事实 ----
    bytes32 internal constant ATTACK_TX = 0x35f8d2f572fceaac9288e5d462117850ef2694786992a8c3f6d02612277b0877;
    uint256 internal constant ATTACK_BLOCK = 11_129_474; // 实测：攻击交易所在区块
    uint256 internal constant FORK_BLOCK = 11_129_473;   // 攻击交易前一个区块

    // ---- Harvest ----
    address internal constant FUSDC = 0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE;
    address internal constant FUSDT = 0x053c80eA73Dc6941F518a68E2FC52Ac45BDE7c9C;
    address internal constant FUSDC_STRATEGY = 0xD55aDA00494D96CE1029C201425249F9dFD216cc;

    // ---- 代币 ----
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // ---- Curve yPool（yDAI/yUSDC/yUSDT/yTUSD，币序 0/1/2/3）----
    address internal constant YPOOL = 0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51;
    address internal constant YDAI = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address internal constant YUSDC = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;
    address internal constant YUSDT = 0x83f798e925BcD4017Eb265844FDDAbb448f1707D;
    address internal constant YTUSD = 0x73a052500105205d34Daf004eAb301916DA8190f;

    // ---- Uniswap V2 ----
    address internal constant UNI_USDT_WETH = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
    address internal constant UNI_USDC_WETH = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    // ---- 真实攻击参数（从链上 trace 逐个解码）----
    uint256 internal constant BORROW_USDT = 18_308_555.417594e6;
    uint256 internal constant TILT_USDT = 17_222_012.640506e6;
    uint256 internal constant BORROW_USDC = 50_000_000e6;
    uint256 internal constant DEPOSIT_USDC = 49_977_468.555526e6;
}
