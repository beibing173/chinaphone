<#
.SYNOPSIS
    DeviceAudit 公共库 —— 被 audit_android.ps1 / endpoint_check.ps1 点引入（dot-source）。
.DESCRIPTION
    只提供函数，不产生副作用。兼容 Windows PowerShell 5.1 与 PowerShell 7+。
    覆盖：adb 定位 / 设备选择 / 超时调用 / UTF-8 解码 / 规则库加载 / 打分评级。
    兼容性注意：5.1 下 ConvertTo-Json 会把单元素数组压成标量，因此本库自定义
    ConvertTo-JsonLike；[ordered] 在 5.1 可用，但数组必须显式 @()。
#>

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
$script:AuditUtf8 = New-Object System.Text.UTF8Encoding $false

# 关键权限清单（规则库里 permission 类型规则主要引用这些名字）
$script:AuditKeyPermissions = @(
    'READ_PRIVILEGED_PHONE_STATE',
    'QUERY_ALL_PACKAGES',
    'PACKAGE_USAGE_STATS',
    'READ_PHONE_STATE',
    'READ_PHONE_NUMBERS',
    'RECORD_AUDIO',
    'CAPTURE_AUDIO_OUTPUT',
    'CAPTURE_VIDEO_OUTPUT',
    'GET_TASKS',
    'REAL_GET_TASKS',
    'READ_SMS',
    'RECEIVE_SMS',
    'SEND_SMS',
    'READ_CALL_LOG',
    'WRITE_CALL_LOG',
    'READ_CONTACTS',
    'READ_EXTERNAL_STORAGE',
    'MANAGE_EXTERNAL_STORAGE',
    'ACCESS_FINE_LOCATION',
    'ACCESS_COARSE_LOCATION',
    'ACCESS_BACKGROUND_LOCATION',
    'RECEIVE_BOOT_COMPLETED',
    'WAKE_LOCK',
    'INTERNET',
    'REQUEST_INSTALL_PACKAGES',
    'SYSTEM_ALERT_WINDOW',
    'BIND_NOTIFICATION_LISTENER_SERVICE',
    'BIND_ACCESSIBILITY_SERVICE',
    'WRITE_SETTINGS',
    'WRITE_SECURE_SETTINGS',
    'CHANGE_WIFI_STATE',
    'MODIFY_AUDIO_SETTINGS'
)

# 风险分级阈值（与 rules.json 的 scoring 段保持一致，缺省值）
$script:AuditDefaultScoring = [ordered]@{
    high   = 70
    medium = 40
    low    = 15
}

# ---------------------------------------------------------------------------
# 文本 / 编码工具
# ---------------------------------------------------------------------------
function New-AuditUtf8Encoding {
    return (New-Object System.Text.UTF8Encoding $false)
}

function ConvertTo-AuditCleanString {
    <# 去掉 adb 输出里的 NUL、BOM、可疑替换符，避免污染 JSON #>
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    $s = $s -replace "`0", ''
    $s = $s.TrimStart([char]0xFEFF)
    return $s
}

function ConvertTo-AuditSafeFileName {
    param([string]$Name, [string]$Fallback = 'unnamed')
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Fallback }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch) { [void]$sb.Append('_') }
        elseif ([int]$ch -lt 32) { [void]$sb.Append('_') }
        else { [void]$sb.Append($ch) }
    }
    $out = $sb.ToString().Trim()
    if ($out.Length -gt 120) { $out = $out.Substring(0, 120) }
    if ([string]::IsNullOrWhiteSpace($out)) { return $Fallback }
    return $out
}

function ConvertTo-AuditJsonLike {
    <#
      自己手写 JSON 序列化：保证数组永远是数组（5.1 的 ConvertTo-Json 在 0/1 元素时会变形），
      并且固定 UTF-8 无 BOM。支持：ordered 字典 / 普通字典 / 数组 / 字符串 / 数字 / 布尔 / null。
    #>
    param(
        [object]$InputObject,
        [int]$Depth = 0,
        [int]$MaxDepth = 64
    )
    if ($Depth -gt $MaxDepth) { return 'null' }
    if ($null -eq $InputObject) { return 'null' }

    $indentUnit = '  '
    $pad = $indentUnit * $Depth
    $padInner = $indentUnit * ($Depth + 1)

    # 字典
    if ($InputObject -is [System.Collections.IDictionary]) {
        $keys = @($InputObject.Keys | ForEach-Object { [string]$_ })
        if ($keys.Count -eq 0) { return '{}' }
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($k in $keys) {
            $v = $InputObject[$k]
            $parts.Add($padInner + (ConvertTo-AuditJsonString $k) + ': ' + (ConvertTo-AuditJsonLike -InputObject $v -Depth ($Depth + 1) -MaxDepth $MaxDepth))
        }
        return '{' + "`r`n" + ($parts -join (',' + "`r`n")) + "`r`n" + $pad + '}'
    }

    # 数组 / 集合
    # 注意：PS 5.1 下对 List[object] 用 @() 会抛 "Argument types do not match"，
    # 必须改用 [System.Linq.Enumerable] 或直接枚举，这里统一转成 ArrayList。
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = New-Object System.Collections.ArrayList
        foreach ($one in $InputObject) { [void]$items.Add($one) }
        if ($items.Count -eq 0) { return '[]' }
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($it in $items) {
            $parts.Add($padInner + (ConvertTo-AuditJsonLike -InputObject $it -Depth ($Depth + 1) -MaxDepth $MaxDepth))
        }
        return '[' + "`r`n" + ($parts -join (',' + "`r`n")) + "`r`n" + $pad + ']'
    }

    # 标量
    if ($InputObject -is [bool]) {
        if ($InputObject) { return 'true' } else { return 'false' }
    }
    if ($InputObject -is [string]) { return (ConvertTo-AuditJsonString $InputObject) }
    if ($InputObject -is [int] -or $InputObject -is [long] -or $InputObject -is [double] -or $InputObject -is [decimal] -or $InputObject -is [single]) {
        $n = [string]([System.Convert]::ToString($InputObject, [System.Globalization.CultureInfo]::InvariantCulture))
        return $n
    }
    if ($InputObject -is [datetime]) { return (ConvertTo-AuditJsonString $InputObject.ToString('o')) }
    # 其余对象：先转字典
    $bag = [ordered]@{}
    foreach ($p in $InputObject.PSObject.Properties) {
        $bag[$p.Name] = $p.Value
    }
    return (ConvertTo-AuditJsonLike -InputObject $bag -Depth $Depth -MaxDepth $MaxDepth)
}

function ConvertTo-AuditJsonString {
    param([string]$Text)
    if ($null -eq $Text) { return '""' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        switch ($ch) {
            '"'  { [void]$sb.Append('\"'); continue }
            '\'  { [void]$sb.Append('\\'); continue }
            "`b" { [void]$sb.Append('\b'); continue }
            "`f" { [void]$sb.Append('\f'); continue }
            "`n" { [void]$sb.Append('\n'); continue }
            "`r" { [void]$sb.Append('\r'); continue }
            "`t" { [void]$sb.Append('\t'); continue }
            default {
                if ($code -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Write-AuditJsonFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$InputObject
    )
    $json = ConvertTo-AuditJsonLike -InputObject $InputObject
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $enc = New-AuditUtf8Encoding
    [System.IO.File]::WriteAllText($Path, $json, $enc)
}

function Write-AuditTextFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $enc = New-AuditUtf8Encoding
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Read-AuditJsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "文件不存在: $Path" }
    $raw = [System.IO.File]::ReadAllText($Path, (New-AuditUtf8Encoding))
    $raw = ConvertTo-AuditCleanString $raw
    return (ConvertFrom-Json -InputObject $raw)
}

# ---------------------------------------------------------------------------
# 路径 / adb 定位
# ---------------------------------------------------------------------------
function Get-AuditScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }
    return (Get-Location).Path
}

function Get-AuditWorkspaceRoot {
    param([string]$From)
    if ([string]::IsNullOrWhiteSpace($From)) { $From = (Get-AuditScriptRoot) }
    $p = Get-Item -LiteralPath $From -ErrorAction SilentlyContinue
    if ($null -eq $p) { return (Get-Location).Path }
    # scripts/ 的上一级即工作区根
    if ($p.PSIsContainer) { return (Split-Path -Parent $p.FullName) }
    return (Split-Path -Parent (Split-Path -Parent $p.FullName))
}

function Find-AuditAdb {
    <#
      依次尝试：显式参数 → PATH → 本机 Android SDK → 常见安装路径。
      找不到返回 $null（由调用方给出友好提示）。
    #>
    param([string]$ExplicitPath)

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates.Add($ExplicitPath)
        $candidates.Add((Join-Path $ExplicitPath 'adb.exe'))
        $candidates.Add((Join-Path $ExplicitPath 'adb'))
    }
    $candidates.Add('adb.exe')
    $candidates.Add('adb')

    $envLocals = @($env:LOCALAPPDATA, $env:USERPROFILE)
    foreach ($base in $envLocals) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidates.Add((Join-Path $base 'Android\Sdk\platform-tools\adb.exe'))
        $candidates.Add((Join-Path $base 'Android\platform-tools\adb.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) {
        $candidates.Add((Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
        $candidates.Add((Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'))
    }
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($pf)) { continue }
        $candidates.Add((Join-Path $pf 'Android\platform-tools\adb.exe'))
    }

    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        try {
            if (Test-Path -LiteralPath $c -PathType Leaf) {
                return (Resolve-Path -LiteralPath $c).Path
            }
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.CommandType -eq 'Application' -and $cmd.Source) {
                return $cmd.Source
            }
        } catch { continue }
    }
    return $null
}

function Find-AuditHdc {
    <# HarmonyOS NEXT（纯血鸿蒙）用 hdc 而不是 adb。找到返回路径，否则 $null。 #>
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add('hdc.exe')
    $candidates.Add('hdc')
    $envLocals = @($env:LOCALAPPDATA, $env:USERPROFILE)
    foreach ($base in $envLocals) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidates.Add((Join-Path $base 'Huawei\Sdk\HarmonyOS-NEXT\toolchains\hdc.exe'))
        $candidates.Add((Join-Path $base 'Huawei\Sdk\toolchains\hdc.exe'))
    }
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($pf)) { continue }
        $candidates.Add((Join-Path $pf 'Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'))
        $candidates.Add((Join-Path $pf 'Huawei\DevEco Studio\tools\hdc\hdc.exe'))
    }
    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        try {
            if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.CommandType -eq 'Application' -and $cmd.Source) { return $cmd.Source }
        } catch { continue }
    }
    return $null
}

# ---------------------------------------------------------------------------
# 进程调用（带超时 + UTF-8 解码）
# ---------------------------------------------------------------------------
function ConvertTo-AuditArgLine {
    <#
      把参数数组拼成 Windows 命令行字符串（cmd 风格的引号转义），
      兼容 PS 5.1 的 ProcessStartInfo.Arguments。参数里带空格/引号时正确加引号。
    #>
    param([string[]]$Arguments = @())
    if (-not $Arguments) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($a in $Arguments) {
        $s = [string]$a
        if ($s -eq '') { $parts.Add('""'); continue }
        if ($s -match '[\s"]') {
            # 反斜杠后跟引号要额外转义，末尾反斜杠要翻倍
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append('"')
            $backslashes = 0
            foreach ($ch in $s.ToCharArray()) {
                if ($ch -eq '\') { $backslashes++; continue }
                if ($ch -eq '"') {
                    [void]$sb.Append(('\' * ($backslashes * 2 + 1)))
                    [void]$sb.Append('"')
                    $backslashes = 0
                    continue
                }
                if ($backslashes -gt 0) {
                    [void]$sb.Append(('\' * $backslashes))
                    $backslashes = 0
                }
                [void]$sb.Append($ch)
            }
            if ($backslashes -gt 0) { [void]$sb.Append(('\' * ($backslashes * 2))) }
            [void]$sb.Append('"')
            $parts.Add($sb.ToString())
        } else {
            $parts.Add($s)
        }
    }
    return ($parts -join ' ')
}

function Invoke-AuditProcess {
    <#
      启动子进程并收集 stdout/stderr，强制 UTF-8 解码（避免中文路径/中文包名乱码），
      带超时；超时则杀进程并标记 TimedOut。绝不向宿主控制台直接写内容，
      因此不会污染 -JsonOnly 这类机器可读模式。
    #>
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 45,
        [switch]$RecordStderr
    )

    $result = [pscustomobject]@{
        ExitCode  = -1
        StdOut    = ''
        StdErr    = ''
        TimedOut  = $false
        Ok        = $false
        Command   = ''
        Error     = ''
    }

    $argList = @()
    if ($Arguments) { $argList = @($Arguments) }
    $result.Command = (@($FilePath) + $argList) -join ' '

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        $result.Error = "找不到可执行文件: $FilePath"
        return $result
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    # 注意：ProcessStartInfo.ArgumentList 只在 .NET Core/PS7 存在，
    # Windows PowerShell 5.1（.NET Framework）必须用 Arguments 字符串，这里统一按 5.1 方式拼。
    $psi.Arguments = (ConvertTo-AuditArgLine -Arguments $argList)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = New-AuditUtf8Encoding
    $psi.StandardErrorEncoding = New-AuditUtf8Encoding

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $result.Error = "启动失败: " + $_.Exception.Message
        return $result
    }

    try {
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $finished = $proc.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)
        if (-not $finished) {
            $result.TimedOut = $true
            try { $proc.Kill() } catch { }
            try { [void]$proc.WaitForExit(2000) } catch { }
        }
        $result.StdOut = ConvertTo-AuditCleanString $outTask.Result
        if ($RecordStderr) {
            $result.StdErr = ConvertTo-AuditCleanString $errTask.Result
        } else {
            try { $result.StdErr = ConvertTo-AuditCleanString $errTask.Result } catch { $result.StdErr = '' }
        }
        if (-not $result.TimedOut) {
            $result.ExitCode = $proc.ExitCode
            $result.Ok = ($proc.ExitCode -eq 0)
        }
        return $result
    } catch {
        $result.Error = "执行异常: " + $_.Exception.Message
        try { if ($proc -and -not $proc.HasExited) { $proc.Kill() } } catch { }
        return $result
    } finally {
        try { $proc.Dispose() } catch { }
    }
}

# ---------------------------------------------------------------------------
# adb 封装
# ---------------------------------------------------------------------------
function Invoke-Adb {
    param(
        [Parameter(Mandatory=$true)][string]$AdbPath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 45
    )
    return (Invoke-AuditProcess -FilePath $AdbPath -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds)
}

function Invoke-AdbShell {
    <#
      adb shell 的 exit code 在部分 ROM 上不可靠，因此额外用输出内容判断。
      多参数时会自动引号拼接（避免厂商 ROM 拆错参）。
    #>
    param(
        [Parameter(Mandatory=$true)][string]$AdbPath,
        [string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$RemoteCommand,
        [int]$TimeoutSeconds = 45
    )
    $joined = ($RemoteCommand | ForEach-Object {
        $s = [string]$_
        if ($s -match '\s' -and -not ($s.StartsWith('"') -and $s.EndsWith('"'))) { '"' + $s + '"' } else { $s }
    }) -join ' '
    $args = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) { $args += @('-s', $Serial) }
    $args += @('shell', $joined)
    $r = Invoke-Adb -AdbPath $AdbPath -Arguments $args -TimeoutSeconds $TimeoutSeconds
    if ($r.StdOut -match 'error: (.*)(device|not found|closed|unauthorized)') {
        $r.Ok = $false
        if ([string]::IsNullOrWhiteSpace($r.StdErr)) { $r.StdErr = $Matches[0] }
    }
    return $r
}

function Get-AdbDevices {
    <# 解析 adb devices -l，返回状态列表（device/unauthorized/offline） #>
    param([Parameter(Mandatory=$true)][string]$AdbPath)

    $r = Invoke-Adb -AdbPath $AdbPath -Arguments @('devices', '-l') -TimeoutSeconds 30
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $r.Ok) {
        return [pscustomobject]@{ Ok = $false; Devices = @(); Raw = $r.StdOut + $r.StdErr; Error = $r.Error }
    }
    foreach ($line in ($r.StdOut -split "`r?`n")) {
        $t = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -match '^(List of devices attached|.*\* daemon.*|\* daemon.*)$') { continue }
        $parts = $t -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $serial = $parts[0]
        $state = $parts[1]
        $model = ''
        $product = ''
        $deviceName = ''
        # 注意：设备行可能只有两列（如 "emulator-5554 offline"），
        # 此时 $parts[2..1] 会生成一个倒序数组并索引越界，必须先判断列数。
        if ($parts.Count -gt 2) {
            foreach ($p in $parts[2..($parts.Count - 1)]) {
                if ($p -like 'model:*') { $model = $p.Substring(6) }
                elseif ($p -like 'product:*') { $product = $p.Substring(8) }
                elseif ($p -like 'device:*') { $deviceName = $p.Substring(7) }
            }
        }
        $list.Add([pscustomobject]@{
            Serial    = $serial
            State     = $state
            Model     = $model
            Product   = $product
            Device    = $deviceName
            IsReady   = ($state -eq 'device')
        })
    }
    return [pscustomobject]@{ Ok = $true; Devices = $list.ToArray(); Raw = $r.StdOut; Error = '' }
}

function Resolve-AuditDevice {
    <#
      处理设备选择与「无设备」分支，返回结构化的前置检查结果。
      Status: ok / no-adb / no-device / unauthorized / offline / hdc-only
    #>
    param(
        [string]$AdbPath,
        [string]$Serial,
        [switch]$AutoStart
    )

    $check = [pscustomobject]@{
        Status        = 'ok'
        AdbPath       = $AdbPath
        Serial        = ''
        Device        = $null
        Devices       = @()
        Message       = ''
        Suggestions   = @()
        HdcPath       = (Find-AuditHdc)
    }

    if ([string]::IsNullOrWhiteSpace($AdbPath) -or -not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
        $check.Status = 'no-adb'
        $check.Message = '未找到 adb 可执行文件。'
        $check.Suggestions = @(
            '安装 Android SDK Platform-Tools，下载地址 https://developer.android.com/studio/releases/platform-tools',
            '或安装 Android Studio 后在 SDK Manager 安装 Platform-Tools',
            '把 platform-tools 目录加入 PATH，或用 -AdbPath 指定 adb.exe 的完整路径',
            '（本机已知路径：C:\Users\17367\AppData\Local\Android\Sdk\platform-tools\adb.exe）'
        )
        return $check
    }

    if ($AutoStart) {
        # 只是唤醒 adb server，失败也不影响后续判断（很多环境 daemon 已在跑）
        [void](Invoke-Adb -AdbPath $AdbPath -Arguments @('start-server') -TimeoutSeconds 25)
    }

    $devResult = Get-AdbDevices -AdbPath $AdbPath
    $check.Devices = $devResult.Devices
    if (-not $devResult.Ok) {
        $check.Status = 'no-device'
        $check.Message = 'adb 无法与服务端通信，可能是 adb server 启动失败。'
        $check.Suggestions = @(
            "手动执行：& `"$AdbPath`" kill-server",
            "再执行：& `"$AdbPath`" start-server",
            '检查是否有其他程序（手机助手/模拟器）占用了 5037 端口'
        )
        return $check
    }

    $ready = @($devResult.Devices | Where-Object { $_.IsReady })
    $anyDevice = @($devResult.Devices)

    if ([string]::IsNullOrWhiteSpace($Serial)) {
        if ($ready.Count -eq 0) {
            # 区分 unauthorized / offline / 完全没插
            if ($anyDevice.Count -gt 0) {
                $unauth = @($anyDevice | Where-Object { $_.State -eq 'unauthorized' })
                $offline = @($anyDevice | Where-Object { $_.State -eq 'offline' })
                if ($unauth.Count -gt 0) {
                    $check.Status = 'unauthorized'
                    $check.Message = ("设备已连接但未授权 USB 调试：{0}" -f (($unauth | ForEach-Object { $_.Serial }) -join ', '))
                    $check.Suggestions = @(
                        '解锁手机，在弹出的「允许 USB 调试吗？」对话框点「允许」（建议勾选"始终允许"）',
                        '如果手机没弹窗：开发者选项 → 撤销 USB 调试授权，然后重新插拔数据线',
                        '确认使用的是数据线而非纯充电线，且 USB 模式不是"仅充电"（改成"传输文件 MTP"）',
                        '部分华为/荣耀机型还需要在开发者选项里打开「仅充电模式下允许 ADB 调试」'
                    )
                } else {
                    $check.Status = 'offline'
                    $check.Message = ("设备处于离线状态：{0}" -f (($offline | ForEach-Object { $_.Serial }) -join ', '))
                    $check.Suggestions = @(
                        '重新插拔数据线，或在手机上关掉再打开 USB 调试',
                        '执行 adb kill-server 后重试',
                        '关闭可能占用 adb 的其他软件（手机管家、助手类工具、模拟器）',
                        '开发者选项 →「撤销 USB 调试授权」后重新授权'
                    )
                }
                return $check
            }

            $check.Status = 'no-device'
            $check.Message = '未检测到已连接的 Android 设备（adb devices 列表为空）。'
            $sug = @(
                '① 用 USB 数据线把手机连到电脑（必须是能传数据的线，不是纯充电线）',
                '② 手机：设置 → 关于手机 → 连续点击「版本号」7 次，开启开发者选项',
                '③ 设置 → 系统和更新 → 开发人员选项 → 打开「USB 调试」（华为/荣耀：还需打开「仅充电模式下允许 ADB 调试」）',
                '④ 手机插入后会在屏幕弹出「允许 USB 调试吗？」，勾选「始终允许」并点确定',
                '⑤ 回到电脑执行 adb devices 确认显示 "device" 而不是 "unauthorized"',
                '⑥ 如果是 HarmonyOS NEXT（纯血鸿蒙，系统里没有「USB 调试」而是「HDC 调试」），adb 无法连接',
                '   需要用 hdc 工具：本机未检测到 hdc，请安装 DevEco Studio 或 HarmonyOS SDK Command Line Tools'
            )
            if ($check.HdcPath) {
                $sug += "   本机已检测到 hdc：$($check.HdcPath)（NEXT 设备请改用 hdc list targets）"
            }
            $check.Suggestions = $sug
            return $check
        }
        if ($ready.Count -gt 1) {
            $check.Status = 'multiple'
            $check.Message = ("检测到 {0} 台可用设备，请用 -Serial 指定要审计哪一台。" -f $ready.Count)
            $check.Suggestions = @(($ready | ForEach-Object { "  -Serial $($_.Serial)   （型号 $($_.Model)）" }))
            return $check
        }
        $check.Serial = $ready[0].Serial
        $check.Device = $ready[0]
        $check.Status = 'ok'
        return $check
    }

    # 指定了 Serial
    $match = @($ready | Where-Object { $_.Serial -eq $Serial })
    if ($match.Count -eq 0) {
        $exists = @($anyDevice | Where-Object { $_.Serial -eq $Serial })
        if ($exists.Count -gt 0 -and $exists[0].State -eq 'unauthorized') {
            $check.Status = 'unauthorized'
            $check.Message = "设备 $Serial 已连接但未授权 USB 调试。"
            $check.Suggestions = @('解锁手机并点「允许」USB 调试授权', '如无弹窗：开发者选项 → 撤销 USB 调试授权 → 重新插拔')
            return $check
        }
        if ($exists.Count -gt 0) {
            $check.Status = 'offline'
            $check.Message = "设备 $Serial 状态为 $($exists[0].State)，不可用。"
            $check.Suggestions = @('重新插拔数据线或 adb kill-server 后重试')
            return $check
        }
        $check.Status = 'no-device'
        $check.Message = "指定的设备 Serial=$Serial 不在 adb devices 列表中。"
        $check.Suggestions = @('不带 -Serial 重新运行让脚本自动选择', '执行 adb devices -l 查看当前可用设备的 Serial')
        return $check
    }
    $check.Serial = $Serial
    $check.Device = $match[0]
    $check.Status = 'ok'
    return $check
}

# ---------------------------------------------------------------------------
# 规则库
# ---------------------------------------------------------------------------
function Get-AuditDefaultRules {
    <# 规则库文件缺失时的兜底：内置最小规则集，保证脚本不会因为缺文件而废掉 #>
    return [pscustomobject]@{
        version = '0.0-fallback'
        updated = '1970-01-01'
        description = 'rules.json 缺失时使用的内置兜底规则集'
        scoring = [pscustomobject]@{ high = 70; medium = 40; low = 15 }
        rules = @(
            [pscustomobject]@{
                id = 'FB-001'; name = '运营商 DM 客户端特征'; enabled = $true; weight = 55
                type = 'package_keyword'; match = '^(com\.)?(dm|dmp)\.'; target = 'package'
                description = '包名疑似运营商设备管理(DM)客户端，可远程下发指令/安装应用。'
                advice = '核对来源，非运营商装机必备则考虑停用。'
            },
            [pscustomobject]@{
                id = 'FB-002'; name = 'priv-app 中的非系统厂商应用'; enabled = $true; weight = 80
                type = 'privapp'; match = ''; target = 'package'
                description = '位于 /system/priv-app，权限高于普通系统应用。'
                advice = '确认是否为厂商预置；非必要则无法卸载但可 pm disable-user 停用。'
            },
            [pscustomobject]@{
                id = 'FB-003'; name = '超权限组合'; enabled = $true; weight = 90
                type = 'permission_combo'; match = @('READ_PHONE_STATE', 'RECORD_AUDIO'); target = 'package'
                description = '同时具备通话状态与录音权限，具备窃听条件。'
                advice = '重点核查，非必要立即停用。'
            },
            [pscustomobject]@{
                id = 'FB-004'; name = '运营商 DM 端点'; enabled = $true; weight = 75
                type = 'endpoint_domain'; match = 'dm\.wo\.com\.cn'; target = 'endpoint'
                description = '联通设备管理平台域名。'
                advice = '如非本人开通的运营商服务，需核实该组件用途。'
            }
        )
    }
}

function Get-AuditRules {
    <#
      加载规则库；文件不存在返回兜底规则并给出 Warning；
      校验失败（JSON 坏了）也返回兜底规则，不抛异常。
    #>
    param([string]$RulesPath, [string]$ScriptRoot)

    if ([string]::IsNullOrWhiteSpace($RulesPath)) {
        if ([string]::IsNullOrWhiteSpace($ScriptRoot)) { $ScriptRoot = (Get-AuditScriptRoot) }
        $RulesPath = Join-Path $ScriptRoot 'rules.json'
    }

    $warnings = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)) {
        $warnings.Add("规则库文件不存在，已使用内置兜底规则: $RulesPath")
        $rules = Get-AuditDefaultRules
    } else {
        try {
            $rules = Read-AuditJsonFile -Path $RulesPath
        } catch {
            $warnings.Add("规则库解析失败（JSON 语法错误？），已使用内置兜底规则: " + $_.Exception.Message)
            $rules = Get-AuditDefaultRules
        }
    }

    $list = New-Object System.Collections.Generic.List[object]
    if ($rules -and $rules.PSObject.Properties['rules']) {
        $idx = 0
        foreach ($r in @($rules.rules)) {
            $idx++
            if ($null -eq $r) { continue }
            $id = ''
            if ($r.PSObject.Properties['id'] -and $r.id) { $id = [string]$r.id } else { $id = "RULE-$idx" }
            $name = ''
            if ($r.PSObject.Properties['name'] -and $r.name) { $name = [string]$r.name } else { $name = $id }
            $type = ''
            if ($r.PSObject.Properties['type'] -and $r.type) { $type = [string]$r.type } else { $type = 'unknown' }
            $enabled = $true
            if ($r.PSObject.Properties['enabled']) { $enabled = [bool]$r.enabled }
            $weight = 10
            if ($r.PSObject.Properties['weight']) {
                try { $weight = [double]$r.weight } catch { $weight = 10 }
            }
            $matchVal = $null
            if ($r.PSObject.Properties['match']) { $matchVal = $r.match }
            $target = 'package'
            if ($r.PSObject.Properties['target'] -and $r.target) { $target = [string]$r.target }
            $norm = [pscustomobject]@{
                Id          = $id
                Name        = $name
                Enabled     = $enabled
                Weight      = $weight
                Type        = $type
                Match       = $matchVal
                Target      = $target
                Description = (Get-AuditProp $r 'description' '')
                Advice      = (Get-AuditProp $r 'advice' '')
            }
            if (-not $enabled) { continue }
            if ($type -eq 'unknown') {
                $warnings.Add("规则 $id 缺少 type 字段，已跳过。")
                continue
            }
            $list.Add($norm)
        }
    }

    # 评分阈值
    $scoring = [ordered]@{ high = 70; medium = 40; low = 15 }
    if ($rules -and $rules.PSObject.Properties['scoring'] -and $rules.scoring) {
        foreach ($k in @('high', 'medium', 'low')) {
            if ($rules.scoring.PSObject.Properties[$k]) {
                try { $scoring[$k] = [double]$rules.scoring.$k } catch { }
            }
        }
    }

    $meta = [ordered]@{
        path        = $RulesPath
        version     = (Get-AuditProp $rules 'version' 'unknown')
        updated     = (Get-AuditProp $rules 'updated' 'unknown')
        description = (Get-AuditProp $rules 'description' '')
        ruleCount   = $list.Count
        warnings    = $warnings.ToArray()
    }

    return [pscustomobject]@{
        Meta    = $meta
        Rules   = $list.ToArray()
        Scoring = $scoring
        Warnings = $warnings.ToArray()
    }
}

function Get-AuditProp {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    try {
        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
    } catch { }
    return $Default
}

# ---------------------------------------------------------------------------
# 分级 / 报告辅助
# ---------------------------------------------------------------------------
function Get-AuditLevel {
    param([double]$Score, [object]$Scoring)
    $high = 70.0; $medium = 40.0
    if ($Scoring) {
        if ($Scoring.Contains('high')) { $high = [double]$Scoring['high'] } elseif ($Scoring.PSObject.Properties['high']) { $high = [double]$Scoring.high }
        if ($Scoring.Contains('medium')) { $medium = [double]$Scoring['medium'] } elseif ($Scoring.PSObject.Properties['medium']) { $medium = [double]$Scoring.medium }
    }
    if ($Score -ge $high) { return '高' }
    if ($Score -ge $medium) { return '中' }
    return '低'
}

function Get-AuditLevelEmoji {
    param([string]$Level)
    switch ($Level) {
        '高' { return '🔴 高' }
        '中' { return '🟠 中' }
        default { return '🟢 低' }
    }
}

function New-AuditTimestamp {
    return (Get-Date).ToString('yyyyMMdd-HHmmss')
}

function Write-AuditLog {
    <#
      -JsonOnly 时必须把日志写到 stderr，避免污染 stdout 上的 JSON。
    #>
    param(
        [string]$Message,
        [ValidateSet('info', 'warn', 'error', 'ok', 'step')]
        [string]$Level = 'info',
        [switch]$ToStderr
    )
    $prefix = switch ($Level) {
        'warn'  { '[警告]' }
        'error' { '[错误]' }
        'ok'    { '[完成]' }
        'step'  { '[步骤]' }
        default { '[信息]' }
    }
    $line = "$prefix $Message"
    if ($ToStderr) { [Console]::Error.WriteLine($line) } else { Write-Host $line }
}

function Write-AuditRule {
    param([switch]$ToStderr)
    $line = '  ' + ('-' * 66)
    if ($ToStderr) { [Console]::Error.WriteLine($line) } else { Write-Host $line }
}

function Test-AuditRegex {
    <# 规则中的正则统一在这里跑，异常时返回 $false 而不是炸掉整个脚本 #>
    param([string]$Text, [string]$Pattern)
    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $false }
    if ($null -eq $Text) { return $false }
    try {
        return ($Text -match $Pattern)
    } catch {
        return $false
    }
}

function Get-AuditMarkdownTable {
    <# 生成 Markdown 表格；单元格里的 | 与换行做转义 #>
    param(
        [string[]]$Headers,
        [object[]]$Rows
    )
    if (-not $Headers -or $Headers.Count -eq 0) { return '' }
    $esc = { param($v)
        if ($null -eq $v) { return '' }
        $s = [string]$v
        $s = $s -replace "`r?`n", ' '
        $s = $s -replace '\|', '\|'
        return $s.Trim()
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| ' + (($Headers | ForEach-Object { & $esc $_ }) -join ' | ') + ' |')
    [void]$sb.AppendLine('| ' + (($Headers | ForEach-Object { '---' }) -join ' | ') + ' |')
    if ($Rows) {
        foreach ($row in $Rows) {
            if ($null -eq $row) { continue }
            $cells = New-Object System.Collections.Generic.List[string]
            # 情况一：行是「列值数组」（最常见，如 @('包名','80','说明')）
            if ($row -is [System.Array] -or ($row -is [System.Collections.IList] -and -not ($row -is [string]) -and -not $row.GetType().Name.StartsWith('PSCustomObject'))) {
                foreach ($v in $row) { $cells.Add((& $esc $v)) }
            }
            # 情况二：行是字典/有序字典，按表头取值
            elseif ($row -is [System.Collections.IDictionary]) {
                foreach ($h in $Headers) { $cells.Add((& $esc $row[$h])) }
            }
            # 情况三：行是对象，按属性名取值
            else {
                foreach ($h in $Headers) { $cells.Add((& $esc (Get-AuditProp $row $h ''))) }
            }
            # 补齐/截断到表头列数，避免错位
            while ($cells.Count -lt $Headers.Count) { $cells.Add('') }
            if ($cells.Count -gt $Headers.Count) {
                $trimmed = New-Object System.Collections.Generic.List[string]
                for ($i = 0; $i -lt $Headers.Count; $i++) { $trimmed.Add($cells[$i]) }
                $cells = $trimmed
            }
            [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
        }
    }
    return $sb.ToString()
}
