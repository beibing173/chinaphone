param(
    [string]$OutputDir = "$PSScriptRoot\..\dist",
    [string]$Version = "1.0.0",
    [string]$Configuration = "Release"
)

<#
.SYNOPSIS
    把电脑版打包成单个 EXE。
.DESCRIPTION
    用 .NET Framework 自带的 csc.exe 编译 pc/launcher/Program.cs，
    不依赖 ps2exe 等外部模块。

    产物：dist/ChinaPhone.exe
    运行时需要同目录（或其上级）有 pc/ 文件夹和其中的 .ps1 脚本。
    另外提供一个「完整包」zip，内含 exe + 脚本 + 说明。

.EXAMPLE
    .\build-exe.ps1 -Version 1.0.0
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== 打包电脑版 EXE (v$Version) ===" -ForegroundColor Cyan

# ── 找 csc.exe ──
$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $csc) {
    Write-Host "[错误] 找不到 csc.exe（.NET Framework 编译器）" -ForegroundColor Red
    Write-Host "请安装 .NET Framework 4.x，或改用其他打包方式。" -ForegroundColor Red
    exit 1
}
Write-Host "编译器: $csc" -ForegroundColor DarkGray

# ── 准备输出目录 ──
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}
$OutputDir = (Resolve-Path $OutputDir).Path

$srcFile = Join-Path $PSScriptRoot 'launcher\Program.cs'
if (-not (Test-Path $srcFile)) {
    Write-Host "[错误] 找不到源码: $srcFile" -ForegroundColor Red
    exit 1
}

$exePath = Join-Path $OutputDir 'ChinaPhone.exe'

# ── 编译 ──
$args = @(
    '/nologo',
    '/target:exe',
    '/platform:anycpu',
    '/optimize+',
    # 注意：PowerShell 用 & 调用外部程序时会对含空格的参数自动加引号，
    # 这里不能再手写引号，否则会变成双重引号（CS2021 路径无效）。
    "/out:$exePath",
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Windows.Forms.dll',
    "/win32icon:$PSScriptRoot\launcher\app.ico"
)

# 图标不存在就跳过，别让编译失败
if (-not (Test-Path "$PSScriptRoot\launcher\app.ico")) {
    $args = $args | Where-Object { $_ -notlike '/win32icon:*' }
}

$args += $srcFile

Write-Host "编译中…" -ForegroundColor DarkGray
$compileOut = & $csc @args 2>&1
$compileCode = $LASTEXITCODE

if ($compileCode -ne 0 -or -not (Test-Path $exePath)) {
    Write-Host "[错误] 编译失败 (exit $compileCode)" -ForegroundColor Red
    $compileOut | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

$exeSize = [math]::Round((Get-Item $exePath).Length / 1KB, 1)
Write-Host "[完成] $exePath  (${exeSize} KB)" -ForegroundColor Green

# ── 打完整包 ──
Write-Host "打包完整 zip…" -ForegroundColor DarkGray

$stageDir = Join-Path ([System.IO.Path]::GetTempPath()) ("chinaphone-stage-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stageDir 'pc') | Out-Null

Copy-Item $exePath (Join-Path $stageDir 'ChinaPhone.exe')
Copy-Item (Join-Path $PSScriptRoot '*.ps1') (Join-Path $stageDir 'pc') -ErrorAction SilentlyContinue
Copy-Item (Join-Path $PSScriptRoot 'rules.json') (Join-Path $stageDir 'pc') -ErrorAction SilentlyContinue
Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $stageDir 'pc') -ErrorAction SilentlyContinue

$readme = @"
ChinaPhone 手机自查工具  v$Version  （电脑版）

使用方法
────────
1. 双击 ChinaPhone.exe
2. 手机用数据线连电脑，开启 USB 调试
3. 按提示授权，等结果

想只查网络端点：
  在命令行执行  ChinaPhone.exe endpoint

常见问题
────────
• 提示「未检测到设备」
  手机需要：设置 → 关于手机 → 连点版本号 7 次
            → 开发人员选项 → 打开「USB 调试」
            → 华为/荣耀还要开「仅充电模式下允许 ADB 调试」

• 提示找不到 adb
  安装 Android SDK Platform-Tools，或把 adb 加入 PATH

• 手机是纯血鸿蒙（HarmonyOS NEXT）
  adb 不可用，需用 hdc，本工具暂不支持

免责
────
只读检查，不修改手机任何设置。
结果是启发式判断，不能证明某应用存在恶意行为。
"@
Set-Content -Path (Join-Path $stageDir '使用说明.txt') -Value $readme -Encoding UTF8

$zipPath = Join-Path $OutputDir "ChinaPhone-PC-v$Version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue

$zipSize = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
Write-Host "[完成] $zipPath  (${zipSize} KB)" -ForegroundColor Green

# ── 输出清单给 CI 用 ──
Write-Host ""
Write-Host "artifacts:"
Write-Host "  $exePath"
Write-Host "  $zipPath"

exit 0
