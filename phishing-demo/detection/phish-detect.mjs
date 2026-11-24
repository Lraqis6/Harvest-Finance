// SPDX-License-Identifier: MIT
// 钓鱼页面 / 邮件样本检测器（教学用启发式扫描，零依赖）
//
// 用法：
//   node phishing-demo/detection/phish-detect.mjs <文件或URL> [--json]
// 说明：这不是浏览器级渲染，只看源码结构与邮件头，因此是"启发式"而非"判定"；
//       真实场景应与 URL 信誉库、沙箱渲染、邮件网关规则叠加使用。
import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const URGENCY = ["立即", "紧急", "24 小时", "24小时", "24小时内", "永久停用", "账号将被", "逾期", "最后通知"];
const BRANDS = ["信息网络中心", "统一身份认证", "校园", "教务处", "财务处", "信息中心"];

const stripTags = (s) => s.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
const safeUrl = (u) => {
  try { return new URL(u); } catch { return null; }
};
const hostOnly = (h) => String(h || "").split(":")[0].toLowerCase();
const isIpOrLoopback = (host) => {
  const h = hostOnly(host);
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(h) || h === "localhost" || h.endsWith(".local");
};

function analyze(source, meta) {
  meta = meta || {};
  const findings = [];
  const add = (id, weight, title, evidence) => findings.push({ id, weight, title, evidence });

  // ---- 链接分析 ----
  const anchors = [];
  const anchorRe = /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let m;
  while ((m = anchorRe.exec(source)) !== null) {
    const href = m[1];
    const text = stripTags(m[2]);
    anchors.push({ href, text });
  }
  const hrefHosts = anchors.map((a) => safeUrl(a.href)).filter(Boolean).map((u) => u.host);

  // R1: 链接指向 IP / 回环地址
  const ipLinks = anchors.filter((a) => {
    const u = safeUrl(a.href);
    return u && isIpOrLoopback(u.host);
  });
  if (ipLinks.length) {
    add("LINK_TO_IP", 25, "存在指向 IP / 本机回环地址的链接",
      ipLinks.slice(0, 3).map((a) => "href=" + a.href + " 文字=\"" + a.text.slice(0, 24) + "\""));
  }

  // R2: 显示地址 ≠ 真实地址（锚文本或正文里的 URL 与 href 的域名不一致）
  const textUrls = [];
  const urlRe = /https?:\/\/[A-Za-z0-9._~:\/?#\[\]@!$&'()*+,;=%-]+/g;
  let u2;
  while ((u2 = urlRe.exec(stripTags(source))) !== null) textUrls.push(u2[0]);
  const textHosts = textUrls.map((x) => safeUrl(x)).filter(Boolean).map((u) => u.host);
  const mismatch = textHosts.filter((h) => hrefHosts.length && !hrefHosts.includes(h));
  if (mismatch.length) {
    add("TEXT_HREF_MISMATCH", 20, "页面里展示的地址与实际链接域名不一致",
      ["展示域名: " + Array.from(new Set(mismatch)).join(", "), "实际链接域名: " + Array.from(new Set(hrefHosts)).join(", ")]);
  }

  // R3: 表单提交到外部绝对地址
  const formRe = /<form\b[^>]*action\s*=\s*["']([^"']+)["']/gi;
  const formActions = [];
  let f;
  while ((f = formRe.exec(source)) !== null) formActions.push(f[1]);
  const absForms = formActions.filter((a) => /^https?:\/\//i.test(a));
  if (absForms.length) {
    add("FORM_TO_EXTERNAL", 15, "登录表单提交到外部绝对地址", absForms.slice(0, 3));
  }

  // R4: 具备凭据收集结构（密码框）
  const hasPassword = /<input\b[^>]*type\s*=\s*["']password["']/i.test(source);
  if (hasPassword) {
    add("CREDENTIAL_FORM", 10, "页面包含密码输入框（具备凭据收集能力）", ["input[type=password] 存在"]);
  }

  // R5: 紧迫性话术
  const hits = URGENCY.filter((k) => source.includes(k));
  if (hits.length) {
    add("URGENCY", Math.min(20, hits.length * 10), "使用紧迫性/威胁性话术施压",
      ["命中关键词: " + hits.join(" / ")]);
  }

  // R6: 邮件头 From / Reply-To 域名不一致（兼容中英文邮件头）
  // 先去掉标签与实体，中英文邮件头都能匹配
  const plain = stripTags(source).replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  const pickHeader = (cnLabel, enLabel) => {
    const cn = plain.match(new RegExp("(?:" + cnLabel + ")\\s*[：:]?\\s*([^\\n|]{0,90})"));
    const en = plain.match(new RegExp("(?:^|\\n)\\s*" + enLabel + "\\s*[:：]\\s*([^\\n|]{0,90})", "i"));
    return (cn && cn[1]) || (en && en[1]) || "";
  };
  const from = pickHeader("发件人", "From") || meta.from || "";
  const replyTo = pickHeader("回复到|回复至|Reply-To", "Reply-To") || meta.replyTo || "";
  if (from && replyTo) {
    const d1 = (from.match(/@([A-Za-z0-9.\-]+)/) || [])[1];
    const d2 = (replyTo.match(/@([A-Za-z0-9.\-]+)/) || [])[1];
    if (d1 && d2 && d1.toLowerCase() !== d2.toLowerCase()) {
      add("REPLY_TO_MISMATCH", 15, "Reply-To 与发件人域名不一致", ["From: " + d1, "Reply-To: " + d2]);
    }
  }

  // R7: 品牌伪装（显示名像官方，域名却不是官方后缀）
  const brandHit = BRANDS.find((b) => source.includes(b));
  const fromDomain = (from.match(/@([A-Za-z0-9.\-]+)/) || [])[1] || "";
  if (brandHit && fromDomain && !/\.edu(\.cn)?$/i.test(fromDomain)) {
    add("BRAND_IMPERSONATION", 15, "发件人显示名疑似冒充校内机构，但域名不是教育机构域名",
      ["显示名含 \"" + brandHit + "\"", "实际域名: " + fromDomain]);
  }

  // R8: punycode / 同形字
  if (/xn--/i.test(source)) {
    add("PUNYCODE", 20, "出现 punycode 域名（xn--），可能是同形字钓鱼", ["包含 xn-- 标记"]);
  }

  // R9: 隐藏 iframe
  if (/<iframe\b[^>]*(display\s*:\s*none|width\s*=\s*["']?0|height\s*=\s*["']?0)/i.test(source)) {
    add("HIDDEN_IFRAME", 10, "存在隐藏 iframe", ["iframe 被设置为不可见"]);
  }

  // R10: 混淆脚本
  if (/atob\s*\(|eval\s*\(/.test(source) && /[A-Za-z0-9+\/]{120,}={0,2}/.test(source)) {
    add("OBFUSCATED_JS", 15, "存在 base64 大块 + eval/atob 的混淆脚本", ["命中 atob/eval + 长 base64"]);
  }

  // R11: 明文 http 链接
  if (/href\s*=\s*["']http:\/\//i.test(source)) {
    add("PLAINTEXT_HTTP", 10, "使用明文 HTTP 链接", ["存在 href=\"http://..."]);
  }

  // 自我声明（演练标记）：只降低"误报"提示，不降低分数——真实攻击者也能写这句话
  const selfDeclared = /DEMO|演练|教学|样例/.test(source);

  const score = Math.min(100, findings.reduce((s, x) => s + x.weight, 0));
  const verdict = score >= 60 ? "高危：高度疑似钓鱼" : score >= 30 ? "可疑：需要人工复核" : "低风险：未发现典型钓鱼特征";
  return { score, verdict, selfDeclared, findings, anchors: anchors.length, textUrls: textUrls.length, hasPassword };
}

async function load(target) {
  if (/^https?:\/\//i.test(target)) {
    const r = await fetch(target, { signal: AbortSignal.timeout(20000) });
    return await r.text();
  }
  return await fs.readFile(target, "utf8");
}

function printReport(name, r, json) {
  if (json) { console.log(JSON.stringify({ target: name, ...r }, null, 2)); return; }
  console.log("=== 钓鱼特征检测：" + name + " ===");
  console.log("风险分：" + r.score + "/100　判定：" + r.verdict);
  console.log("锚点数：" + r.anchors + "　正文 URL 数：" + r.textUrls + "　密码框：" + (r.hasPassword ? "有" : "无"));
  console.log("");
  if (!r.findings.length) { console.log("未命中任何规则。"); return; }
  for (const x of r.findings) {
    console.log("[" + String(x.weight).padStart(2) + "] " + x.id + "  " + x.title);
    for (const e of x.evidence) console.log("        - " + e);
  }
  if (r.selfDeclared) console.log("\n注：页面里出现了「演练/教学/样例」等自我声明。真实攻击者也可以写这句话，因此本项不扣分，不能当作安全依据。");
}

async function main() {
  const args = process.argv.slice(2);
  const json = args.includes("--json");
  const target = args.find((a) => !a.startsWith("--"));
  if (!target) {
    console.error("用法: node phishing-demo/detection/phish-detect.mjs <文件或URL> [--json]");
    process.exit(1);
  }
  const src = await load(target);
  const r = analyze(src, {});
  printReport(target, r, json);
  process.exit(r.score >= 60 ? 1 : 0);
}

export { analyze };

const __isMain = (() => {
  try {
    const here = fileURLToPath(import.meta.url);
    const entry = process.argv[1] ? path.resolve(process.argv[1]) : "";
    return here === entry;
  } catch { return false; }
})();

if (__isMain) {
  main().catch((e) => { console.error(e.message || e); process.exit(2); });
}
