# 本地钓鱼演练套件（加分项·选修部分）

> 课程：网络安全技术　定位：**安全教育演练**，不是可投放的攻击工具。

## 一、这是什么

一套在本机运行的"钓鱼演练 + 钓鱼检测"演示环境，包含三部分：

| 模块 | 文件 | 作用 |
| --- | --- | --- |
| 钓鱼邮件样本 | `mail/phish-mail.html` | 仿冒"信息网络中心"的紧急停用通知，演示邮件欺骗的几个关键点 |
| 仿冒登录页 | `server/templates/login.html` | 仿冒校园统一身份认证页面，配合本地服务器做"被钓"体验 |
| 本地演练服务器 | `server/app.mjs` | 只监听 127.0.0.1，提交后返回"你被钓了"的安全教育页 |
| 钓鱼检测器 | `detection/phish-detect.mjs` | 对页面/邮件样本做启发式打分，输出证据清单（防守视角） |

## 二、明确的边界（必读）

这套东西的设计目标是**让人知道自己是怎么被骗的**，因此刻意阉割了真实钓鱼木马的全部关键能力：

| 能力 | 真实钓鱼木马 | 本项目 |
| --- | --- | --- |
| 对外发送邮件 | 群发 | **没有发信代码**，样本只能本地打开 |
| 收集凭据 | 保存明文并外发 | 只记录**掩码 + 长度 + SHA-256**，且只写本机文件 |
| 监听地址 | 0.0.0.0 公网可访问 | **硬编码 127.0.0.1**，外网无法连接 |
| 上线/回连 | C2 回连 | **全程无任何外部网络请求** |
| 持久化 | 注册表/计划任务/开机自启 | **没有任何持久化代码** |
| 免杀/加壳/反分析 | 有 | **完全没有** |
| 伪装跳转 | 登录成功后跳到真实站点 | 返回"你刚刚被钓了"的教育页 |

启动服务器必须显式确认，否则直接退出：

```bash
node phishing-demo/server/app.mjs --ack-demo          # 或设置 PHISH_DEMO_ACK=i-understand
```

## 三、运行步骤

```bash
# 1. 启动演练页面（仅本机）
node phishing-demo/server/app.mjs --ack-demo
# 浏览器打开 http://127.0.0.1:8787/ ，随便输入一个假账号密码

# 2. 打开钓鱼邮件样本（静态文件，不会发送）
#    双击 phishing-demo/mail/phish-mail.html 即可

# 3. 用检测器给样本打分
node phishing-demo/detection/phish-detect.mjs phishing-demo/mail/phish-mail.html
node phishing-demo/detection/phish-detect.mjs phishing-demo/server/templates/login.html
```

## 四、实测结果

| 样本 | 风险分 | 判定 | 主要证据 |
| --- | --- | --- | --- |
| 钓鱼邮件样本 | **100/100** | 高危 | 链接指向 127.0.0.1、显示地址≠真实地址、紧迫话术、Reply-To 域不一致、冒充校内机构、明文 HTTP |
| 演练登录页 | 10/100 | 低风险 | 仅命中"含密码输入框" |

演练服务器实测（HTTP 交互）：

```
GET  /       -> 200，页面含"安全演练页面"横幅，响应头 x-edu-demo: true
POST /login  -> 200，返回"你刚刚被钓了"教育页
写入 captures/demo-captures.jsonl：
{"demo":true,"username":"2023123456","passwordMasked":"D*********3","passwordLength":11,
 "passwordSha256":"db9f57e3…e3c","remote":"127.0.0.1", ...}
```

注意最后这条：**连演练都只记录掩码和哈希**，而真实钓鱼站点记录的是明文——这正是危害所在。

## 五、页面截图

| 文件 | 内容 |
| --- | --- |
| docs/images/phish_mail.png | 钓鱼邮件样本的实际渲染效果（浏览器截图） |
| docs/images/phish_login.png | 仿冒登录页的实际渲染效果 |
| docs/images/phish_login_served.png | 演练服务器下发版本（顶部带红色演练横幅，需运行截图脚本生成） |

重新生成截图（需在本机普通终端运行，Chromium 需要访问命名管道，普通沙箱内会失败）：

```powershell
powershell -ExecutionPolicy Bypass -File script\screenshot-pages.ps1
python script\build-report.py      # 截图更新后重建报告
```

## 五、目录

```
phishing-demo/
├─ README.md                 本文件
├─ server/app.mjs            本地演练服务器（127.0.0.1 + 显式确认 + 无外发）
├─ server/templates/login.html  仿冒登录页模板
├─ mail/phish-mail.html      钓鱼邮件样本（含"显示地址 vs 真实地址"对比说明）
├─ detection/phish-detect.mjs 钓鱼检测器（启发式，6 类规则）
└─ docs/演练说明.md           演练设计、手法剖析、检测对抗思路

docs/images/phish_*.png       页面截图（由 script/screenshot-pages.ps1 生成）
```

## 六、免责声明

本套件仅用于课程教学中的安全意识演练，页面与邮件均为本地静态样本，不发送、不收集真实凭据、不连接任何外部服务。请勿将其改造成面向真实人群的钓鱼工具；在任何环境下使用仿冒页面获取他人凭据均可能构成违法犯罪。
