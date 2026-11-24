# Harvest Finance 闪电贷 + 预言机操纵攻击复现

> 网络安全技术课程大作业 · 真实漏洞复现与防护
> 目标：在本地隔离环境（Foundry Fork）中完整复现 2020-10-26 Harvest Finance 被闪电贷操纵 Curve yPool 报价、进而套利约 2400 万美元的事件，并给出指纹识别模块与防护组件。

## 一句话原理

Harvest 的 fUSDC 金库用「策略报告的本金价值 ÷ 份额总量」给份额定价，而策略的本金价值又依赖 Curve yPool 中 yToken 的报价（`getPricePerFullShare` / `get_virtual_price`）。
攻击者因此可以在**同一笔交易内**：

1. 闪电贷借出 USDT，砸进 Curve yPool，把 yPool 的报价压低约 0.9%；
2. 此时用借来的 5000 万 USDC **低价存入**金库，换到比正常情况更多的 fUSDC 份额；
3. 再把 USDC 砸回 yPool 让报价复位；
4. 按复位后的价格**赎回**份额，拿回比存入更多的 USDC；
5. 归还闪电贷，差额就是利润。

整个流程原子执行，不需要任何自有资金。

## 目录结构

```
├─ src/
│  ├─ HarvestAttacker.sol          # 攻击合约（嵌套闪电贷 + 4 步操纵 + 复利多轮）
│  ├─ ArbGateProbe.sol             # 3% 套利闸门探针（用 revert data 回传结果）
│  ├─ Addresses.sol                # 全部主网地址与实测常量
│  ├─ interfaces/                  # 最小接口（含 coins(int128) 等易错点注释）
│  ├─ libraries/FlashFee.sol       # ceil(amount*1000/997) 还款精度
│  ├─ mocks/FlashLoanProbe.sol     # 纯闪电贷借还探针
│  └─ defense/ManipulationGuard.sol# 防护组件：时间加权均价 + 偏差阈值
├─ test/
│  ├─ 00_Premise.t.sol             # 测试0 前提校验（地址/币序/报价/份额价）
│  ├─ 01_FlashLoan.t.sol           # 测试1 纯闪电贷借还 + 少还 1 wei 会 revert
│  ├─ 02_CurveSwap.t.sol           # 测试2 单次兑换的价位位移（必须 < 3%）
│  ├─ 03_DepositRedeem.t.sol       # 测试3 低价存入 / 高位赎回
│  ├─ 04_FullAttack.t.sol          # 测试4 完整攻击（1 轮 + 3 轮）
│  ├─ 05_RepayMath.t.sol           # 测试5 还款取整精度
│  ├─ 06_ArbGate.t.sol             # 测试6 3% 套利闸门边界
│  └─ 07_Defense.t.sol             # 测试7 防护组件拦截操纵
├─ script/
│  ├─ fingerprint.mjs              # ★ 指纹识别模块（零依赖 Node）
│  ├─ fork_replay.mjs              # 不用 foundry 也能复核攻击结果
│  ├─ audit_addresses.mjs          # 地址与链上事实审计
│  └─ lib/eth.mjs                  # keccak256 / ABI / JSON-RPC（零依赖）
├─ phishing-demo/                  # 加分项：本地钓鱼演练套件（惰性、无外发）
│  ├─ server/app.mjs               #   仅监听 127.0.0.1 的演练服务器
│  ├─ mail/phish-mail.html         #   钓鱼邮件样本（不发送）
│  ├─ detection/phish-detect.mjs   #   钓鱼检测器（6 类规则、0-100 打分）
│  └─ docs/演练说明.md             #   欺骗点剖析与合规边界
├─ script/screenshot-pages.ps1     #   用 Edge 无头模式给演练页面截图
├─ script/build-report.py          #   由 docs/report_source.md 生成设计报告 docx
├─ artifacts/                      # 运行期字节码快照（供 fork_replay 使用）
├─ foundry.toml                    # solc 0.8.10 + evm istanbul（与 2020 链上环境同代）
└─ docs/                           # 设计报告、运行记录
```

## 环境要求

| 依赖 | 说明 |
| --- | --- |
| Foundry | `curl -L https://foundry.paradigm.xyz | bash && foundryup`；记录 `forge --version` 到报告 |
| 归档 RPC | 必须能读 2020 年历史状态（Alchemy / QuickNode / BlastAPI / dRPC 等） |
| Node 18+ | 只跑 script/ 下的辅助脚本时需要（无需 npm install） |

```bash
cp .env.example .env      # 填入 MAINNET_RPC_URL
# PowerShell 加载 .env
Get-Content .env | ForEach-Object { if ($_ -match '^(.+?)=(.*)') { [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process") } }
```

## 快速开始

```bash
forge build
forge test -vv                                  # 全部用例
forge test --match-test test_ThreeRoundsMatchRealTransaction -vv   # 与链上真实交易对账
```

没有 Foundry 时，也可以只用 Node 复核（依赖 RPC 支持 `eth_call` 的 stateOverride）：

```bash
node script/audit_addresses.mjs --rpc "$MAINNET_RPC_URL" --block 11129473
node script/fork_replay.mjs    --rpc "$MAINNET_RPC_URL" --block 11129473 --rounds 1,3
node script/fingerprint.mjs    --rpc "$MAINNET_RPC_URL" --block 11129473
```

## 实测结果（本机复跑，fork 到区块 11,129,473）

| 指标 | 数值 |
| --- | --- |
| 单轮攻击净利 | **101,783.785134 USDC** |
| 三轮复利净利 | **715,118.195636 USDC** |
| 第三轮存入 / 份额 / 赎回 | 50,574,381.418380 / 52,333,322.836527 / 50,894,567.909953 |
| 链上真实交易第三轮 | 50,574,381.356760 / 52,333,322.565136 / 50,894,567.817318 |
| 偏差 | < 1e-7 相对误差（几十 wei 级） |
| 份额价位移 | 0.980007 → 0.971261（-0.89%，低于 3% 闸门） |

> 关键点：三轮复现结果与 2020 年那笔真实交易的第三轮数值几乎逐 wei 一致，
> 说明 fork 区块、币序、报价路径、存款/赎回顺序全部对齐。

## 与《三次修正版实施方案》的差异（第四轮修正）

实测复核后，本仓库在方案基础上又修正了 4 处：

1. **fork 区块错了**：攻击交易实际在 **11,129,474**（不是 11,129,490），应 fork 到 **11,129,473**。
   证据：该区块上 `get_dy_underlying(2,1,17,222,012.640506)` = 17,216,702.568694，与链上成交 17,216,703.208672 只差 0.64 USDC；
   若 fork 到 11,129,489 则会偏差约 480 USDC。
2. **"单轮净利 619,408 USDC"是误读**：619,408 是"第二轮赎回额 50,596,877 − 第二轮存入额 49,977,468"的口径错位。
   第一轮真实赎回应为 **50,298,684.215219**，扣除两笔闪电贷手续费后单轮净利约 **10.2 万 USDC**。
3. **真实交易是"一次借 USDC、内部跑 3 轮复利"**：三轮回拉额固定 17,239,234.653146，存入额逐轮递增
   （49,977,468.56 → 50,276,170.50 → 50,574,381.36），不是每轮重新借一次。
4. **Curve 池的 USDC 现金只有约 304 万**（其余在 Compound 里），单笔砸盘超过约 2000 万 USDT 会因提现流动性不足而 revert；
   也就是说 3% 闸门在实践中由"池子能拿出多少"先兜住了。

## 加分项：本地钓鱼演练

见 [phishing-demo/README.md](phishing-demo/README.md)。定位是**安全意识演练**而不是可投放的攻击工具：
邮件样本只在本机打开、演练服务器硬编码 127.0.0.1 且无任何外发、密码只记录掩码与 SHA-256、提交后返回"你刚刚被钓了"的教育页。

```bash
node phishing-demo/server/app.mjs --ack-demo         # 打开 http://127.0.0.1:8787/
node phishing-demo/detection/phish-detect.mjs phishing-demo/mail/phish-mail.html
```

实测：钓鱼邮件样本 100/100 高危（命中 6 类特征），演练登录页仅 10/100（只命中"含密码框"）。

## 防护思路

见 `src/defense/ManipulationGuard.sol`：用时间加权均价（EMA 近似 TWAP）给份额定价，并对瞬时价相对均价的偏差设阈值（示例 0.5%）。
单笔闪电贷交易无法改变已固化的历史观测，因此"砸盘—存入—复位—赎回"在同一次交易内必然被拒。
测试 7 验证了该组件能拦下真实攻击幅度（0.89% > 0.5%），同时放行 0.1% 的正常波动。

## 免责声明

本项目仅用于网络安全课程教学与学术研究：所有操作只在本地隔离环境的 Fork 上运行，不连接、不部署、不攻击任何真实链上协议；不使用真实资金；不涉及免杀、加壳、反分析、隐蔽化等手段。历史合约地址、交易哈希、区块号均来自公开区块浏览器数据，仅作为链上事实核查用途。使用者须遵守所在国家和地区的法律法规。
