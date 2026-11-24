// SPDX-License-Identifier: MIT
// 本地钓鱼演练服务器（教学用，惰性、无外发）
//
// 设计边界（重要）：
//   1. 只监听 127.0.0.1，默认端口 8787，外部无法访问；
//   2. 启动必须显式确认（--ack-demo 或 PHISH_DEMO_ACK=i-understand），避免被误当成真钓鱼页面使用；
//   3. 提交的密码不落盘明文：只记录掩码、长度与 SHA-256，用于说明"即便是演练也能看出泄露后果"；
//   4. 全程不发起任何外部网络请求，不发送邮件，不写自启动项，不做任何持久化；
//   5. 提交后返回的是"安全教育页"，不是"登录成功跳转"——刻意让演练闭环停在认知层面。
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const TEMPLATE = path.join(__dirname, "templates", "login.html");
const CAPTURE_DIR = path.join(ROOT, "captures");
const CAPTURE_FILE = path.join(CAPTURE_DIR, "demo-captures.jsonl");

export const BANNER = '<div style="position:sticky;top:0;z-index:9;background:#b91c1c;color:#fff;'
  + 'font:13px/1.7 -apple-system,Segoe UI,Microsoft YaHei,sans-serif;padding:10px 16px;text-align:center;">'
  + '&#9888; 安全演练页面（DEMO）：本页面由《网络安全技术》课程作业在本机生成，不会收集真实凭据，请勿输入真实密码。'
  + '</div>';

/** 密码脱敏：只保留长度与首尾字符，其余用 * 代替 */
export function maskPassword(pw) {
  if (!pw) return "";
  if (pw.length <= 2) return "*".repeat(pw.length);
  return pw[0] + "*".repeat(Math.max(1, pw.length - 2)) + pw[pw.length - 1];
}

export function sha256(s) {
  return crypto.createHash("sha256").update(String(s), "utf8").digest("hex");
}

/** 记录一次"被钓到"的事件（不写明文密码） */
export function simulateCapture({ username, password, userAgent, remote }) {
  const record = {
    demo: true,
    ts: new Date().toISOString(),
    username: String(username || "").slice(0, 64),
    passwordMasked: maskPassword(password),
    passwordLength: password ? String(password).length : 0,
    passwordSha256: password ? sha256(password) : null,
    userAgent: String(userAgent || "").slice(0, 160),
    remote: remote || "",
    note: "DEMO 记录：真实钓鱼站点会保存明文口令并外发；本文件仅用于教学演示，不含明文。",
  };
  fs.mkdirSync(CAPTURE_DIR, { recursive: true });
  fs.appendFileSync(CAPTURE_FILE, JSON.stringify(record) + "\n", "utf8");
  return record;
}

function educationPage(record) {
  return '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>演练结果</title>'
    + '<style>body{font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;background:#f8fafc;color:#1f2937;margin:0;padding:40px}'
    + '.box{max-width:760px;margin:0 auto;background:#fff;border-radius:12px;padding:32px 36px;box-shadow:0 10px 30px rgba(15,35,70,.1)}'
    + 'h1{font-size:22px;margin:0 0 6px;color:#b91c1c}code{background:#f1f5f9;padding:2px 6px;border-radius:4px}'
    + 'li{line-height:2;font-size:14px}.tag{display:inline-block;background:#fef3c7;color:#92400e;border-radius:999px;padding:3px 10px;font-size:12px}</style>'
    + '</head><body><div class="box">'
    + '<h1>你刚刚"被钓"了 —— 这是一次教学演练</h1>'
    + '<p class="tag">DEMO · 没有真实凭据被收集</p>'
    + '<p style="font-size:14px;line-height:1.9">如果你在真实的钓鱼页面上做了同样的操作，攻击者此刻已经拿到：</p>'
    + '<ul>'
    + '<li>账号：<code>' + (record.username || "(空)") + '</code></li>'
    + '<li>密码掩码：<code>' + (record.passwordMasked || "(空)") + '</code>（真实站点会存明文）</li>'
    + '<li>密码长度：<code>' + record.passwordLength + '</code>，SHA-256 前 12 位：<code>' + (record.passwordSha256 || "").slice(0, 12) + '</code></li>'
    + '</ul>'
    + '<p style="font-size:14px;line-height:1.9">下次遇到这类页面，先做这四件事：</p>'
    + '<ol>'
    + '<li>看域名：真实系统一定在 <code>*.edu.cn</code> 之类的官方域名下，而不是 IP 或奇怪后缀；</li>'
    + '<li>悬停链接：鼠标移到按钮上，看浏览器状态栏的真实地址是否与文字一致；</li>'
    + '<li>别信紧迫感："24 小时内停用"是最常见的施压话术；</li>'
    + '<li>走官方入口：从学校主页进入认证系统，而不是从邮件链接进入。</li>'
    + '</ol>'
    + '<p style="color:#6b7280;font-size:13px">记录已写入 <code>phishing-demo/captures/demo-captures.jsonl</code>（仅掩码与哈希）。</p>'
    + '</div></body></html>';
}

function notFound(res) {
  res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
  res.end("404");
}

/** 读取模板并注入演练横幅 */
export function renderLoginPage() {
  const html = fs.readFileSync(TEMPLATE, "utf8");
  return html.replace("<body>", "<body>" + BANNER);
}

export function createDemoServer() {
  return http.createServer((req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/login")) {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8", "x-edu-demo": "true" });
      res.end(renderLoginPage());
      return;
    }
    if (req.method === "POST" && url.pathname === "/login") {
      let body = "";
      req.on("data", (c) => {
        body += c;
        if (body.length > 4096) req.destroy();
      });
      req.on("end", () => {
        const params = new URLSearchParams(body);
        const record = simulateCapture({
          username: params.get("username"),
          password: params.get("password"),
          userAgent: req.headers["user-agent"],
          remote: req.socket.remoteAddress,
        });
        res.writeHead(200, { "content-type": "text/html; charset=utf-8", "x-edu-demo": "true" });
        res.end(educationPage(record));
      });
      return;
    }
    if (req.method === "GET" && url.pathname === "/captures") {
      const exists = fs.existsSync(CAPTURE_FILE);
      res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
      res.end(exists ? fs.readFileSync(CAPTURE_FILE, "utf8") : "[]");
      return;
    }
    notFound(res);
  });
}

function main() {
  const ack = process.argv.includes("--ack-demo") || process.env.PHISH_DEMO_ACK === "i-understand";
  if (!ack) {
    console.error("拒绝启动：这是安全演练程序。确认只在本机教学环境下使用，请加 --ack-demo 参数。");
    process.exit(2);
  }
  const port = Number(process.env.PORT || 8787);
  const host = "127.0.0.1"; // 硬编码：绝不监听外部地址
  const server = createDemoServer();
  server.listen(port, host, () => {
    console.log("钓鱼演练服务器已启动： http://" + host + ":" + port + "/");
    console.log("仅监听本机回环地址；不会发送邮件、不发起任何外部请求。按 Ctrl+C 结束。");
  });
}

const __isMain = (() => {
  try {
    const here = fileURLToPath(import.meta.url);
    const entry = process.argv[1] ? path.resolve(process.argv[1]) : "";
    return here === entry;
  } catch { return false; }
})();

if (__isMain) {
  main();
}
