// SPDX-License-Identifier: MIT
// 极简以太坊工具库（零依赖）：keccak256 / ABI 编解码 / JSON-RPC
const RC = [0x0000000000000001n,0x0000000000008082n,0x800000000000808an,0x8000000080008000n,0x000000000000808bn,0x0000000080000001n,0x8000000080008081n,0x8000000000008009n,0x000000000000008an,0x0000000000000088n,0x0000000080008009n,0x000000008000000an,0x000000008000808bn,0x800000000000008bn,0x8000000000008089n,0x8000000000008003n,0x8000000000008002n,0x8000000000000080n,0x000000000000800an,0x800000008000000an,0x8000000080008081n,0x8000000000008080n,0x0000000080000001n,0x8000000080008008n];
const ROT = [[0,36,3,41,18],[1,44,10,45,2],[62,6,43,15,61],[28,55,25,21,56],[27,20,39,8,14]];
const M = (1n << 64n) - 1n;
const rotl = (x, n) => ((x << BigInt(n)) | (x >> BigInt(64 - n))) & M;

function keccakF(st) {
  const C = new Array(5).fill(0n), D = new Array(5).fill(0n), B = new Array(25).fill(0n);
  for (let round = 0; round < 24; round++) {
    for (let x = 0; x < 5; x++) C[x] = st[x] ^ st[x + 5] ^ st[x + 10] ^ st[x + 15] ^ st[x + 20];
    for (let x = 0; x < 5; x++) D[x] = C[(x + 4) % 5] ^ rotl(C[(x + 1) % 5], 1);
    for (let i = 0; i < 25; i++) st[i] ^= D[i % 5];
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) B[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(st[x + 5 * y], ROT[x][y]);
    for (let y = 0; y < 5; y++) for (let x = 0; x < 5; x++) st[x + 5 * y] = B[x + 5 * y] ^ ((~B[(x + 1) % 5 + 5 * y]) & M & B[(x + 2) % 5 + 5 * y]);
    st[0] ^= RC[round];
  }
}

export function keccak256(data) {
  const rate = 136;
  const padLen = rate - (data.length % rate);
  const padded = new Uint8Array(data.length + padLen);
  padded.set(data);
  padded[data.length] ^= 0x01;
  padded[padded.length - 1] ^= 0x80;
  const st = new Array(25).fill(0n).map(() => 0n);
  for (let off = 0; off < padded.length; off += rate) {
    for (let i = 0; i < rate / 8; i++) {
      let lane = 0n;
      for (let b = 7; b >= 0; b--) lane = (lane << 8n) | BigInt(padded[off + i * 8 + b]);
      st[i] ^= lane;
    }
    keccakF(st);
  }
  const out = new Uint8Array(32);
  for (let i = 0; i < 4; i++) {
    let lane = st[i];
    for (let b = 0; b < 8; b++) { out[i * 8 + b] = Number(lane & 0xffn); lane >>= 8n; }
  }
  return out;
}

export const hex = (u) => "0x" + Array.from(u).map((b) => b.toString(16).padStart(2, "0")).join("");
export const sel = (sig) => hex(keccak256(new TextEncoder().encode(sig))).slice(0, 10);
export const pad32 = (v) => BigInt(v).toString(16).padStart(64, "0");
export const addr32 = (a) => a.toLowerCase().replace(/^0x/, "").padStart(64, "0");
export const enc = (sig, ...args) => sel(sig) + args.map((a) => (typeof a === "string" && a.startsWith("0x") && a.length === 42 ? addr32(a) : pad32(a))).join("");
export const decUint = (ret, i = 0) => (!ret || ret === "0x" ? null : BigInt("0x" + ret.slice(2 + i * 64, 2 + (i + 1) * 64)));
export const decAddr = (ret, i = 0) => (ret && ret.length >= 2 + (i + 1) * 64 ? "0x" + ret.slice(2 + i * 64 + 24, 2 + (i + 1) * 64) : null);
export function decStr(ret) {
  if (!ret || ret === "0x" || ret.length < 130) return null;
  const body = ret.slice(2);
  const len = Number(BigInt("0x" + body.slice(64, 128)));
  if (len === 0 || len > 256) return null;
  return Buffer.from(body.slice(128, 128 + len * 2), "hex").toString("utf8");
}

export const toBlock = (b) => (typeof b === "number" ? "0x" + b.toString(16) : b || "latest");

export class Rpc {
  constructor(url, opts) {
    opts = opts || {};
    // url 支持用逗号分隔多个端点，失败时自动切换到下一个
    this.urls = String(url).split(",").map((u) => u.trim()).filter(Boolean);
    this.url = this.urls[0];
    this.block = toBlock(opts.block || "latest");
    this.timeout = opts.timeout || 45000;
    this.calls = 0;
  }
  async request(method, params) {
    this.calls++;
    let lastErr = null;
    for (const u of this.urls) {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const r = await fetch(u, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: method, params: params }),
            signal: AbortSignal.timeout(this.timeout),
          });
          if (!r.ok) throw new Error("HTTP " + r.status + " from " + u);
          const j = await r.json();
          if (j.error) throw new Error(method + ": " + j.error.message);
          return j.result;
        } catch (e) {
          lastErr = e;
          await new Promise((res) => setTimeout(res, 300));
        }
      }
    }
    throw lastErr;
  }
  call(to, data, block) {
    return this.request("eth_call", [{ to: to, data: data }, toBlock(block || this.block)]);
  }
  code(addr, block) {
    return this.request("eth_getCode", [addr, toBlock(block || this.block)]);
  }
  storage(addr, slot, block) {
    return this.request("eth_getStorageAt", [addr, slot, toBlock(block || this.block)]);
  }
}

export function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const val = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : "true";
      args[key] = val;
    } else args._.push(a);
  }
  return args;
}

export const CHAIN = {
  USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  USDT: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  DAI: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
  TUSD: "0x0000000000085d4780B73119b644AE5ecd22b376",
  FUSDC: "0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE",
  FUSDT: "0x053c80eA73Dc6941F518a68E2FC52Ac45BDE7c9C",
  FUSDC_STRATEGY: "0xD55aDA00494D96CE1029C201425249F9dFD216cc",
  YPOOL: "0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51",
  UNI_USDT_WETH: "0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852",
  UNI_USDC_WETH: "0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc",
};

export const FORK_BLOCK = 11129473;
