// SPDX-License-Identifier: MIT
// 地址与事实审计：把复现依赖的每一个地址、币序、储备、报价在归档节点上复核一遍
//
// 用法：node script/audit_addresses.mjs --rpc <ARCHIVE_RPC> [--block 11129473]
import { Rpc, CHAIN, FORK_BLOCK, sel, enc, decUint, decAddr, decStr, parseArgs } from "./lib/eth.mjs";
import { fileURLToPath } from "node:url";
import path from "node:path";

export const TARGETS = [
  { name: "fUSDC 金库（= 份额代币）", addr: CHAIN.FUSDC, calls: ["name()", "symbol()", "underlying()", "strategy()", "getPricePerFullShare()", "totalSupply()"] },
  { name: "fUSDT 金库", addr: CHAIN.FUSDT, calls: ["name()", "underlying()", "getPricePerFullShare()"] },
  { name: "fUSDC 策略", addr: CHAIN.FUSDC_STRATEGY, calls: ["depositArbCheck()"] },
  { name: "Curve yPool", addr: CHAIN.YPOOL, calls: ["get_virtual_price()", "A()"] },
  { name: "Uniswap USDT/WETH", addr: CHAIN.UNI_USDT_WETH, calls: ["token0()", "token1()", "getReserves()"] },
  { name: "Uniswap USDC/WETH", addr: CHAIN.UNI_USDC_WETH, calls: ["token0()", "token1()", "getReserves()"] },
];

function format(label, ret, sig) {
  if (ret === null) return label + ": <call failed>";
  if (sig === "name()" || sig === "symbol()") return label + ": " + decStr(ret);
  if (sig === "underlying()" || sig === "strategy()" || sig === "token0()" || sig === "token1()") return label + ": " + decAddr(ret);
  if (sig === "getReserves()") return label + ": " + decUint(ret, 0) + " / " + decUint(ret, 1);
  if (sig === "get_virtual_price()" || sig === "getPricePerFullShare()" || sig === "A()" || sig === "totalSupply()" || sig === "depositArbCheck()")
    return label + ": " + decUint(ret);
  return label + ": " + ret;
}

export async function audit(rpcUrl, block) {
  const rpc = new Rpc(rpcUrl, { block: block || FORK_BLOCK });
  const lines = [];
  const data = [];
  for (const t of TARGETS) {
    const code = await rpc.code(t.addr);
    const size = (code.length - 2) / 2;
    lines.push("[" + (size > 0 ? "OK " : "!! ") + "] " + t.name + " " + t.addr + "  code=" + size + "B");
    const row = { name: t.name, address: t.addr, codeSize: size, values: {} };
    for (const sig of t.calls) {
      let ret = null;
      try { ret = await rpc.call(t.addr, sel(sig)); } catch {}
      row.values[sig] = ret;
      lines.push("      " + format(sig, ret, sig));
    }
    data.push(row);
  }
  // Curve 币序：必须用 coins(int128)
  lines.push("");
  lines.push("Curve yPool 币序（coins(int128)）：");
  const coins = [];
  for (let i = 0; i < 4; i++) {
    let a = null;
    try { a = decAddr(await rpc.call(CHAIN.YPOOL, enc("coins(int128)", i))); } catch {}
    coins.push(a);
    lines.push("      coins(" + i + ") = " + a);
  }
  // 报价复核：17,222,012.640506 USDT -> ? USDC
  const dx = 17_222_012_640_506n;
  let dy = null;
  try { dy = decUint(await rpc.call(CHAIN.YPOOL, enc("get_dy_underlying(int128,int128,uint256)", 2, 1, dx))); } catch {}
  lines.push("");
  lines.push("报价复核 get_dy_underlying(2 -> 1, 17,222,012.640506 USDT) = " + dy + "（链上成交 17,216,703.208672 USDC）");
  return { lines: lines.join("\n"), data: data, coins: coins, dy: dy ? dy.toString() : null };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = args.rpc || process.env.MAINNET_RPC_URL;
  if (!rpcUrl) { console.error("用法: node script/audit_addresses.mjs --rpc <ARCHIVE_RPC> [--block N]"); process.exit(1); }
  const block = Number(args.block || FORK_BLOCK);
  const res = await audit(rpcUrl, block);
  console.log("=== 地址与事实审计 @ block " + block + " ===");
  console.log(res.lines);
  if (args.json) {
    const fs = await import("node:fs/promises");
    await fs.writeFile(args.json, JSON.stringify(res, null, 2), "utf8");
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
  main().catch((e) => { console.error(e.message || e); process.exit(1); });
}
