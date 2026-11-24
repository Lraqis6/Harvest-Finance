// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ForkBase.sol";
import {Mainnet} from "../src/Addresses.sol";
import {IHarvestVaultLike, IHarvestStrategyLike} from "../src/interfaces/IHarvestVaultLike.sol";
import {ICurveYPoolLike} from "../src/interfaces/ICurveYPoolLike.sol";
import {IUniswapV2PairLike} from "../src/interfaces/IUniswapV2PairLike.sol";
import {IERC20Like} from "../src/interfaces/IERC20Like.sol";

/// @title 测试 0：前提校验（这一步不过，后面都不用跑）
contract PremiseTest is ForkBase {
    function setUp() public {
        _fork();
    }

    function test_VaultUnderlyingIsUSDC() public {
        if (!forked) return;
        assertEq(IHarvestVaultLike(Mainnet.FUSDC).underlying(), Mainnet.USDC, "underlying");
        assertEq(IHarvestVaultLike(Mainnet.FUSDC).name(), "FARM_USDC", "name");
        assertEq(IHarvestVaultLike(Mainnet.FUSDC).symbol(), "fUSDC", "symbol");
        assertEq(IHarvestVaultLike(Mainnet.FUSDT).underlying(), Mainnet.USDT, "underlying USDT");
    }

    function test_CurveCoinOrder() public {
        if (!forked) return;
        ICurveYPoolLike pool = ICurveYPoolLike(Mainnet.YPOOL);
        assertEq(pool.coins(0), Mainnet.YDAI);
        assertEq(pool.coins(1), Mainnet.YUSDC);
        assertEq(pool.coins(2), Mainnet.YUSDT);
        assertEq(pool.coins(3), Mainnet.YTUSD);
        assertEq(pool.A(), 1000, "A");
        // 注意：coins(uint256) 在这个池子上 revert，只能走 coins(int128)
    }

    function test_ForkStateMatchesOnchainFill() public {
        if (!forked) return;
        uint256 dy = ICurveYPoolLike(Mainnet.YPOOL).get_dy_underlying(2, 1, Mainnet.TILT_USDT);
        // 链上真实成交：17,222,012.640506 USDT -> 17,216,703.208672 USDC
        uint256 onchain = 17_216_703.208672e6;
        uint256 diff = dy > onchain ? dy - onchain : onchain - dy;
        assertLt(diff * 10_000 / onchain, 1, "deviation < 0.01%");
    }

    function test_VaultSharePrice() public {
        if (!forked) return;
        assertEq(IHarvestVaultLike(Mainnet.FUSDC).getPricePerFullShare(), 980_007, "ppfs");
        assertEq(IHarvestVaultLike(Mainnet.FUSDC).totalSupply(), 127_588_335.242035e6, "supply");
    }

    function test_PairReservesAndTokenOrder() public {
        if (!forked) return;
        IUniswapV2PairLike usdtPair = IUniswapV2PairLike(Mainnet.UNI_USDT_WETH);
        assertEq(usdtPair.token0(), 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "WETH first");
        assertEq(usdtPair.token1(), Mainnet.USDT, "USDT second");
        (, uint112 r1, ) = usdtPair.getReserves();
        assertGt(uint256(r1), 200_000_000e6, "USDT reserve");

        IUniswapV2PairLike usdcPair = IUniswapV2PairLike(Mainnet.UNI_USDC_WETH);
        assertEq(usdcPair.token0(), Mainnet.USDC, "USDC first");
        (uint112 r0, , ) = usdcPair.getReserves();
        assertGt(uint256(r0), 300_000_000e6, "USDC reserve");
    }

    function test_StrategyArbGateOpenBeforeAttack() public {
        if (!forked) return;
        address strategy = IHarvestVaultLike(Mainnet.FUSDC).strategy();
        assertEq(strategy, Mainnet.FUSDC_STRATEGY);
        assertTrue(IHarvestStrategyLike(strategy).depositArbCheck(), "arb gate open before attack");
    }
}
