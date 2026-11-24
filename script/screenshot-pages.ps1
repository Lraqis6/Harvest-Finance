# 用 Edge 无头模式给钓鱼演练页面截图（在本机普通终端运行，不要在受限沙箱内运行）
# 用法: powershell -ExecutionPolicy Bypass -File script\screenshot-pages.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$edge = @(
  "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
  "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $edge) { throw "找不到 msedge.exe，请手动截图或安装 Edge" }

$outDir = Join-Path $root "docs\images"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$profileDir = Join-Path $env:TEMP ("dsh-shot-" + [Guid]::NewGuid().ToString("N"))

function Shot([string]$url, [string]$file, [int]$w, [int]$h) {
  $args = @("--headless=new", "--disable-gpu", "--no-sandbox", "--hide-scrollbars", "--no-first-run",
            "--virtual-time-budget=5000", "--user-data-dir=$profileDir",
            "--window-size=$w,$h", "--screenshot=$(Join-Path $outDir $file)", $url)
  & $edge @args 2>$null | Out-Null
  $p = Join-Path $outDir $file
  if (Test-Path $p) { "OK   $file  $((Get-Item $p).Length) B" } else { "FAIL $file" }
}

# 1) 钓鱼邮件样本（静态文件）
$mail = (New-Object System.Uri((Join-Path $root "phishing-demo\mail\phish-mail.html"))).AbsoluteUri
Shot $mail "phish_mail.png" 1200 980

# 2) 仿冒登录页模板（受害者看到的样子）
$login = (New-Object System.Uri((Join-Path $root "phishing-demo\server\templates\login.html"))).AbsoluteUri
Shot $login "phish_login.png" 1200 860

# 3) 演练服务器下发的版本（顶部带红色演练横幅）——需要先起服务
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
  $proc = Start-Process -FilePath $nodeCmd.Source -ArgumentList @("phishing-demo\server\app.mjs", "--ack-demo") -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 2
  try {
    Shot "http://127.0.0.1:8787/" "phish_login_served.png" 1200 900
  } finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
} else {
  "跳过 phish_login_served.png：未找到 node"
}

Remove-Item -Recurse -Force $profileDir -ErrorAction SilentlyContinue
"截图已输出到 docs\images\"
