// SPDX-License-Identifier: MIT
// Harvest Finance 金库指纹识别模块（零依赖 Node ESM）
//
// 用途：判断某个地址是不是"用 Curve yPool 给份额定价的 Harvest 一代金库"，
//       也就是存在闪电贷 + 预言机操纵风险的组件。
// 指纹维度：
//   1. 字节码哈希 / 字节码长度          —— 同版本部署的"文件哈希"
//   2. 函数选择器集合                    —— 组件的"特定路径"
//   3. name()/symbol()/decimals()        —— 组件的"版本号标识"
//   4. underlying() + strategy()         —— 组件依赖链
//   5. 策略字节码里是否硬编码了 yPool 地址 —— 判定是否依赖可被操纵的 Curve 报价
//   6. storage slot 0 是否指向实现合约    —— 识别 VaultProxy 代理模式
import { Rpc, CHAIN, FORK_BLOCK, enc, decUint, decAddr, decStr, keccak256, hex, sel } from "./lib/eth.mjs";
import { fileURLToPath } from "node:url";
import path from "node:path";

/** Harvest 一代金库的已知部署（都是 Curve yPool 计价，理论上都可被同类手法攻击） */
export const KNOWN_VAULTS = {
  "0xf0358e8c3cd5fa238a29301d0bea3d63a17bedbe": { symbol: "fUSDC", underlying: CHAIN.USDC, note: "2020-10-26 被攻击，损失约 $24M" },
  "0x053c80ea73dc6941f518a68e2fc52ac45bde7c9c": { symbol: "fUSDT", underlying: CHAIN.USDT, note: "同一攻击者用同一手法攻击" },
  "0xab7fa2b2985bccfc13c6d86f1ace9f86d910ab4c": { symbol: "fDAI", underlying: CHAIN.DAI, note: "同批部署" },
  "0x7674622c63bee7f46e86a4a5a18976693d54441b": { symbol: "fTUSD", underlying: CHAIN.TUSD, note: "同批部署" },
};

/** 金库（VaultProxy）与策略需要出现的函数选择器 */
export const VAULT_SELECTORS = {
  "deposit(uint256)": sel("deposit(uint256)"),
  "withdraw(uint256)": sel("withdraw(uint256)"),
  "getPricePerFullShare()": sel("getPricePerFullShare()"),
  "underlying()": sel("underlying()"),
  "strategy()": sel("strategy()"),
  "governance()": sel("governance()"),
  "totalSupply()": sel("totalSupply()"),
};

const STRATEGY_SELECTORS = {
  "depositArbCheck()": sel("depositArbCheck()"),
  "balanceOfPool()": sel("balanceOfPool()"),
  "harvest()": sel("harvest()"),
  "want()": sel("want()"),
};

export const codeHash = (code) => hex(keccak256(Buffer.from(code.replace(/^0x/, ""), "hex")));

function addrEmbeddedIn(code, addr) {
  // 把地址作为 32 字节 ABI 常量或 20 字节 PUSH20 立即数在字节码里查找
  const c = code.toLowerCase().replace(/^0x/, "");
  const a = addr.toLowerCase().replace(/^0x/, "");
  const padded = "000000000000000000000000" + a;
  return c.includes(a) || c.includes(padded);
}

async function tryCall(rpc, to, sig, block) {
  try {
    return await rpc.call(to, sig, block);
  } catch {
    return null;
  }
}

async function tryCallArgs(rpc, to, sig, args, block) {
  try {
    return await rpc.call(to, enc(sig, ...args), block);
  } catch {
    return null;
  }
}

/** 识别单个地址 */
export async function fingerprint(rpc, address, opts) {
  opts = opts || {};
  const block = opts.block || FORK_BLOCK;
  const code = await rpc.code(address, block);
  const report = {
    address,
    block,
    codeSize: Math.max(0, (code.length - 2) / 2),
    codeHash: codeHash(code),
    isContract: code !== "0x",
    checks: {},
    dependency: {},
    score: 0,
    verdict: "NOT_A_HARVEST_VAULT",
    note: "",
  };
  if (!report.isContract) {
    report.note = "该地址没有合约代码（空地址/EOA），不可能是金库";
    return report;
  }

  // 1) 代理识别：优先 EIP-1967 槽位，其次 storage slot 0
  //    Harvest 的 VaultProxy 用的就是 EIP-1967 的 implementation 槽，
  //    所以所有一代金库的"代理字节码"完全相同，可以直接当指纹用。
  let impl = null;
  const EIP1967_IMPL = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
  for (const slot of [EIP1967_IMPL, "0x0"]) {
    try {
      const raw = await rpc.storage(address, slot, block);
      if (!raw || /^0x0+$/.test(raw)) continue;
      const candidate = "0x" + raw.slice(-40);
      if (/^0x0{40}$/.test(candidate)) continue;
      const implCode = await rpc.code(candidate, block);
      if (implCode !== "0x") { impl = candidate; break; }
    } catch {}
  }
  report.implementation = impl;

  // 2) 函数选择器指纹
  const va = {};
  for (const [name, s] of Object.entries(VAULT_SELECTORS)) va[name] = code.includes(s.slice(2));
  report.checks.vaultSelectors = va;
  // 代理模式下选择器在实现合约里
  if (impl) {
    const implCode = await rpc.code(impl, block);
    for (const [name, s] of Object.entries(VAULT_SELECTORS)) va[name] = implCode.includes(s.slice(2));
    report.implementationCodeHash = codeHash(implCode);
  }

  // 3) 版本标识
  const nameRet = await tryCall(rpc, address, sel("name()"), block);
  const symRet = await tryCall(rpc, address, sel("symbol()"), block);
  const decRet = await tryCall(rpc, address, sel("decimals()"), block);
  report.name = decStr(nameRet);
  report.symbol = decStr(symRet);
  report.decimals = decRet ? Number(decUint(decRet)) : null;

  // 4) 依赖链：underlying + strategy
  const undRet = await tryCall(rpc, address, sel("underlying()"), block);
  report.underlying = undRet ? decAddr(undRet) : null;
  const stratRet = await tryCall(rpc, address, sel("strategy()"), block);
  report.strategy = stratRet ? decAddr(stratRet) : null;

  if (report.underlying) {
    const us = await tryCall(rpc, report.underlying, sel("symbol()"), block);
    report.underlyingSymbol = decStr(us);
  }

  // 5) 策略：是否实现 depositArbCheck，是否硬编码 yPool
  if (report.strategy) {
    const stratCode = await rpc.code(report.strategy, block);
    report.dependency.strategyIsContract = stratCode !== "0x";
    if (stratCode !== "0x") {
      const arbRet = await tryCall(rpc, report.strategy, sel("depositArbCheck()"), block);
      report.dependency.depositArbCheck = arbRet !== null;
      report.dependency.arbGateOpenNow = arbRet ? decUint(arbRet) === 1n : null;
      report.dependency.usesCurveYPool = addrEmbeddedIn(stratCode, CHAIN.YPOOL);
      report.dependency.curvePoolAddress = report.dependency.usesCurveYPool ? CHAIN.YPOOL : null;
      const selHits = {};
      for (const [n, s] of Object.entries(STRATEGY_SELECTORS)) selHits[n] = stratCode.includes(s.slice(2));
      report.dependency.strategySelectors = selHits;
    }
  }

  // 6) 规模数据（用于判断值不值得打）
  const ppfsRet = await tryCall(rpc, address, sel("getPricePerFullShare()"), block);
  report.pricePerShare = ppfsRet ? Number(decUint(ppfsRet)) / 1e6 : null;
  const supplyRet = await tryCall(rpc, address, sel("totalSupply()"), block);
  report.totalSupply = supplyRet ? Number(decUint(supplyRet)) / (report.decimals === 18 ? 1e18 : 1e6) : null;
  const balRet = await tryCallArgs(rpc, CHAIN.USDC, "balanceOf(address)", [address], block);
  report.usdcBalance = balRet ? Number(decUint(balRet)) / 1e6 : null;

  // 7) 打分
  let score = 0;
  const v = report.checks.vaultSelectors;
  const core = ["deposit(uint256)", "withdraw(uint256)", "getPricePerFullShare()", "underlying()", "strategy()"];
  const hits = core.filter((k) => v[k]).length;
  score += hits * 8; // 最多 40
  if (report.name && /^FARM_/.test(report.name)) score += 15;
  if (report.symbol && /^f[A-Z]/.test(report.symbol)) score += 5;
  if (report.underlyingSymbol && ["USDC", "USDT", "DAI", "TUSD"].includes(report.underlyingSymbol)) score += 10;
  if (report.dependency.depositArbCheck) score += 10;
  if (report.dependency.usesCurveYPool) score += 20;
  report.score = score;

  const known = KNOWN_VAULTS[address.toLowerCase()];
  if (known) report.knownDeployment = known;

  if (score >= 80 && report.dependency.usesCurveYPool) {
    report.verdict = "HARVEST_V1_CURVE_ORACLE_VAULT";
    report.note = "疑似 Harvest 一代金库：份额价依赖 Curve yPool 实时报价，存在闪电贷+预言机操纵风险";
  } else if (score >= 55) {
    report.verdict = "HARVEST_LIKE_VAULT";
    report.note = "疑似 Harvest 系金库，但未能确认 Curve 报价依赖，需要人工复核策略";
  } else if (score >= 30) {
    report.verdict = "PARTIAL_MATCH";
    report.note = "只匹配到部分特征，可能是其他项目的金库或代理合约";
  } else {
    report.verdict = "NOT_A_HARVEST_VAULT";
    report.note = "特征不足";
  }
  return report;
}

/** 批量扫描并输出表格 */
export async function scan(rpcUrl, addresses, opts) {
  const rpc = new Rpc(rpcUrl, { block: (opts && opts.block) || FORK_BLOCK });
  const rows = [];
  for (const a of addresses) rows.push(await fingerprint(rpc, a, opts));
  return rows;
}

export function formatTable(rows) {
  const lines = [];
  lines.push("地址                                       代码字节  名称        符号     底层币   策略闸门  Curve依赖  评分  结论");
  for (const r of rows) {
    lines.push(
      [
        r.address,
        String(r.codeSize).padStart(8),
        String(r.name || "-").padEnd(10),
        String(r.symbol || "-").padEnd(8),
        String(r.underlyingSymbol || "-").padEnd(8),
        String(r.dependency.depositArbCheck === undefined ? "-" : r.dependency.depositArbCheck ? "yes" : "no").padEnd(8),
        String(r.dependency.usesCurveYPool === undefined ? "-" : r.dependency.usesCurveYPool ? "yes" : "no").padEnd(9),
        String(r.score).padStart(4),
        r.verdict,
      ].join("  ")
    );
  }
  return lines.join("\n");
}

async function main() {
  const { parseArgs } = await import("./lib/eth.mjs");
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = args.rpc || process.env.MAINNET_RPC_URL;
  if (!rpcUrl) {
    console.error("用法: node script/fingerprint.mjs --rpc <ARCHIVE_RPC> --block 11129473 <address...>");
    process.exit(1);
  }
  const addrs = args._.length ? args._ : Object.keys(KNOWN_VAULTS);
  const block = Number(args.block || FORK_BLOCK);
  const rows = await scan(rpcUrl, addrs, { block });
  console.log("=== Harvest 金库指纹识别 @ block " + block + " ===");
  console.log(formatTable(rows));
  console.log("\n=== 详情 ===");
  for (const r of rows) {
    console.log(JSON.stringify(r, null, 2));
  }
  if (args.json) {
    const fs = await import("node:fs/promises");
    await fs.writeFile(args.json, JSON.stringify(rows, null, 2), "utf8");
    console.log("已写入 " + args.json);
  }
}

const __isMain = (() => {
  try {
    const here = fileURLToPath(import.meta.url);
    const entry = process.argv[1] ? path.resolve(process.argv[1]) : "";
    return here === entry;
  } catch { return false; }
})();

if (__isMain) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
