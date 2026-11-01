<#
.SYNOPSIS
    端点排查脚本 —— 检查设备是否存在回连运营商 DM 平台或可疑明文 HTTP 端点的组件。
.DESCRIPTION
    两种工作模式：
      1. 设备模式（默认）：通过 adb 读取已安装应用、网络连接、DNS 缓存，
         对照 rules.json 里的 endpoint_domain 规则，给出「候选组件 → 可能端点」映射。
      2. 文件模式（-FromFile）：读取已有的 netstat/dumpsys 输出文本做离线分析。

    不依赖抓包也能工作：即使拿不到实时连接，也能基于「包名特征 → 已知端点」的
    映射表给出高置信度候选（这正是小米样本 SystemHelper 的识别方式）。

.PARAMETER OutputRoot
    报告根目录，默认 <工作区>\reports。
.PARAMETER Serial
    多设备时指定。
.PARAMETER FromFile
    离线模式：读取指定文本文件（adb shell netstat 或 dumpsys netstats 的输出）。
.PARAMETER JsonOnly
    只输出 JSON 到 stdout。

.EXAMPLE
    .\endpoint_check.ps1
.EXAMPLE
    adb shell netstat > net.txt
    .\endpoint_check.ps1 -FromFile .\net.txt
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [string]$Serial = '',
    [string]$RulesPath = '',
    [string]$AdbPath = '',
    [string]$FromFile = '',
    [switch]$JsonOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$commonPath = Join-Path $scriptRoot 'DeviceAudit.Common.ps1'
if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) {
    Write-Error "找不到公共库: $commonPath"
    exit 2
}
. $commonPath

$toStderr = [bool]$JsonOnly
function Log { param([string]$m, [string]$lv = 'info') Write-AuditLog -Message $m -Level $lv -ToStderr:$toStderr }

# ---------------------------------------------------------------------------
# 已知「包名特征 → 端点」映射表（离线也能判定的高置信度线索）
# ---------------------------------------------------------------------------
$script:KnownMappings = @(
    [pscustomobject]@{
        Pattern     = '(?i)(systemhelper|mobiletools)'
        Endpoints   = @('http://dm.wo.com.cn:18080/register')
        Operator    = '中国联通（CUCC）'
        PlainHttp   = $true
        Note        = '小米样本 SystemHelper：运营商 DM 客户端，按联通 DM 规范向 dm.wo.com.cn 注册。明文 HTTP。'
    },
    [pscustomobject]@{
        Pattern     = '(?i)(guardprovider|securitycenter)'
        Endpoints   = @('fraud-detection.engine.miui.com', 'flash.sec.miui.com')
        Operator    = '厂商（小米）'
        PlainHttp   = $false
        Note        = '小米样本 系统安全组件：上报第三方应用清单与仿冒应用检测结果。'
    },
    [pscustomobject]@{
        Pattern     = '(?i)(cmcc|chinamobile|10086)'
        Endpoints   = @('dm.10086.cn')
        Operator    = '中国移动（CMCC）'
        PlainHttp   = $false
        Note        = '中国移动 DM 平台端点特征。'
    },
    [pscustomobject]@{
        Pattern     = '(?i)(ctcc|chinatelecom|189)'
        Endpoints   = @('dm.189.cn')
        Operator    = '中国电信（CTCC）'
        PlainHttp   = $false
        Note        = '中国电信 DM 平台端点特征。'
    },
    [pscustomobject]@{
        Pattern     = '(?i)(hicloud|huawei.*log|hwouc)'
        Endpoints   = @('logservice.hicloud.com', 'hwid.platform.hicloud.com')
        Operator    = '厂商（华为）'
        PlainHttp   = $false
        Note        = '华为 HMS 遥测/日志上报端点。'
    }
)

# 运营商 DM 域名总表（用于从文本里提取）
# 端口只认 ':' 后面的数字；'/' 后面是 IP，不能当端口（否则 dm.wo.com.cn/202.99.1.1 会把 202 误判成端口）
$script:DmDomainRegex = '(?i)(dm\.wo\.com\.cn|dm\.10086\.cn|dm\.189\.cn|dm\.ctcc|dm\.cmcc)(?::([0-9]{1,5})\b)?'
# 若文本中出现「域名/IP:端口」形式，额外尝试抓真实端口
$script:DmHostPortRegex = '(?i)(dm\.wo\.com\.cn|dm\.10086\.cn|dm\.189\.cn|dm\.ctcc|dm\.cmcc)[:/]([0-9]{1,3}(?:\.[0-9]{1,3}){3}):([0-9]{1,5})'

# ---------------------------------------------------------------------------
# 工作区
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $wsRoot = Get-AuditWorkspaceRoot -From $scriptRoot
    $OutputRoot = Join-Path $wsRoot 'reports'
}
$stamp = New-AuditTimestamp
$outDir = Join-Path $OutputRoot ("endpoint-$stamp")
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$ruleSet = Get-AuditRules -RulesPath $RulesPath -ScriptRoot $scriptRoot
$endpointRules = @($ruleSet.Rules | Where-Object { $_.Type -eq 'endpoint_domain' })
Log ("加载端点规则 {0} 条" -f $endpointRules.Count) 'ok'

# ---------------------------------------------------------------------------
# 收集文本（设备模式 or 离线模式）
# ---------------------------------------------------------------------------
$rawText = ''
$packages = New-Object System.Collections.Generic.List[object]
$deviceInfo = $null
$mode = 'device'

if (-not [string]::IsNullOrWhiteSpace($FromFile)) {
    $mode = 'file'
    if (-not (Test-Path -LiteralPath $FromFile -PathType Leaf)) {
        Log "离线文件不存在: $FromFile" 'error'
        exit 1
    }
    $rawText = [System.IO.File]::ReadAllText($FromFile, (New-Object System.Text.UTF8Encoding $false))
    Log "离线模式：读取 $FromFile（$($rawText.Length) 字符）" 'ok'
} else {
    if ([string]::IsNullOrWhiteSpace($AdbPath)) { $AdbPath = Find-AuditAdb }
    $dev = Resolve-AuditDevice -AdbPath $AdbPath -Serial $Serial -AutoStart
    if ($dev.Status -ne 'ok') {
        if ($JsonOnly) {
            [Console]::Out.Write((ConvertTo-AuditJsonLike -InputObject ([ordered]@{
                tool = 'ChinaPhone EndpointCheck'; status = 'aborted'
                reason = $dev.Status; message = $dev.Message; suggestions = @($dev.Suggestions)
            })))
        } else {
            Write-Host ''
            Write-AuditRule
            Write-Host '  无法继续：' -ForegroundColor Yellow -NoNewline
            Write-Host $dev.Message
            Write-AuditRule
            foreach ($s in $dev.Suggestions) { Write-Host ("    - {0}" -f $s) }
            Write-AuditRule
        }
        exit 1
    }
    $targetSerial = $dev.Serial
    Log "目标设备: $targetSerial" 'ok'

    # 设备信息
    $mk = (Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('getprop ro.product.manufacturer')).StdOut
    $md = (Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('getprop ro.product.model')).StdOut
    $deviceInfo = [ordered]@{
        serial = $targetSerial
        manufacturer = (ConvertTo-AuditCleanString $mk).Trim()
        model        = (ConvertTo-AuditCleanString $md).Trim()
    }

    # 已安装应用
    $pkgR = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('pm list packages') -TimeoutSeconds 90
    if ($pkgR.Ok) {
        foreach ($line in ($pkgR.StdOut -split "`r?`n")) {
            $t = $line.Trim()
            if ($t -match '^package:(.+)$') {
                $packages.Add([pscustomobject]@{ Name = $Matches[1] })
            }
        }
    }
    Log ("  已安装应用 {0} 个" -f $packages.Count) 'ok'

    # 网络连接（需要 root 或 shell 权限；失败不算错）
    Log '采集网络连接（netstat）...' 'step'
    $net = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('netstat -tn') -TimeoutSeconds 60
    if ($net.Ok -and $net.StdOut) {
        $rawText += "`r`n=== netstat ===`r`n" + (ConvertTo-AuditCleanString $net.StdOut)
        Log '  netstat 采集成功' 'ok'
    } else {
        Log '  netstat 采集失败（多数非 root 设备被限制），改用映射表判定' 'warn'
    }

    # DNS 缓存（需要 root）
    $dns = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('ip -s neigh') -TimeoutSeconds 30
    if ($dns.Ok -and $dns.StdOut) {
        $rawText += "`r`n=== neigh ===`r`n" + (ConvertTo-AuditCleanString $dns.StdOut)
    }

    # dumpsys netstats（部分设备可读，含域名/连接记录）
    $nstats = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('dumpsys netstats full') -TimeoutSeconds 90
    if ($nstats.Ok -and $nstats.StdOut) {
        $rawText += "`r`n=== netstats ===`r`n" + (ConvertTo-AuditCleanString $nstats.StdOut)
        Log '  netstats 采集成功' 'ok'
    }
}

# ---------------------------------------------------------------------------
# 分析：文本里的 DM 域名
# ---------------------------------------------------------------------------
Log '分析端点...' 'step'
$domainsFound = New-Object System.Collections.Generic.List[object]

# 先抓「域名/IP:端口」形式，能拿到确切端口
$hostPort = @{}
foreach ($m in [regex]::Matches($rawText, $script:DmHostPortRegex)) {
    $hostPort[$m.Groups[1].Value.ToLower()] = $m.Groups[3].Value
}

foreach ($m in [regex]::Matches($rawText, $script:DmDomainRegex)) {
    $d = $m.Groups[1].Value.ToLower()
    $port = ''
    if ($hostPort.ContainsKey($d)) { $port = $hostPort[$d] }
    elseif ($m.Groups[2].Success) { $port = $m.Groups[2].Value }
    $dup = $false
    foreach ($e in $domainsFound) { if ($e.Domain -eq $d -and $e.Port -eq $port) { $dup = $true; break } }
    if ($dup) { continue }
    $domainsFound.Add([pscustomobject]@{
        Domain = $d
        Port   = $port
        Match  = $m.Value.Trim()
        Rule   = 'R006'
    })
}

# ---------------------------------------------------------------------------
# 分析：包名 → 已知端点映射
# ---------------------------------------------------------------------------
$mapped = New-Object System.Collections.Generic.List[object]
foreach ($p in $packages) {
    foreach ($mp in $script:KnownMappings) {
        if (Test-AuditRegex -Text $p.Name -Pattern $mp.Pattern) {
            $mapped.Add([pscustomobject]@{
                Package   = $p.Name
                Operator  = $mp.Operator
                Endpoints = $mp.Endpoints
                PlainHttp = $mp.PlainHttp
                Note      = $mp.Note
            })
        }
    }
}

# 规则命中的端点
$ruleHits = New-Object System.Collections.Generic.List[object]
foreach ($r in $endpointRules) {
    foreach ($d in $domainsFound) {
        if (Test-AuditRegex -Text $d.Match -Pattern ([string]$r.Match)) {
            $ruleHits.Add([pscustomobject]@{
                Rule = $r.Id; Name = $r.Name; Weight = $r.Weight
                Domain = $d.Domain; Port = $d.Port
                Description = $r.Description; Advice = $r.Advice
            })
        }
    }
    # 包名映射也算命中（离线可判定的高置信度线索）
    foreach ($p in $packages) {
        if (Test-AuditRegex -Text $p.Name -Pattern ([string]$r.Match)) {
            $ruleHits.Add([pscustomobject]@{
                Rule = $r.Id; Name = $r.Name; Weight = $r.Weight
                Domain = '(包名特征命中，待抓包确认)'; Port = ''
                Description = $r.Description; Advice = $r.Advice
                Package = $p.Name
            })
        }
    }
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------
$report = [ordered]@{
    tool      = 'ChinaPhone EndpointCheck'
    version   = '1.0.0'
    timestamp = (Get-Date).ToString('o')
    status    = 'ok'
    mode      = $mode
    device    = $deviceInfo
    stats     = [ordered]@{
        packages      = $packages.Count
        dmDomains     = $domainsFound.Count
        packageMapped = $mapped.Count
        ruleHits      = $ruleHits.Count
    }
    dmDomains     = @($domainsFound | ForEach-Object { [ordered]@{ domain = $_.Domain; port = $_.Port; match = $_.Match } })
    packageMapping= @($mapped | ForEach-Object {
        [ordered]@{
            package = $_.Package; operator = $_.Operator
            endpoints = @($_.Endpoints); plainHttp = $_.PlainHttp; note = $_.Note
        }
    })
    ruleHits      = @($ruleHits | ForEach-Object {
        [ordered]@{
            rule = $_.Rule; name = $_.Name; weight = $_.Weight
            domain = $_.Domain; port = $_.Port
            package = (Get-AuditProp $_ 'Package' '')
            description = $_.Description; advice = $_.Advice
        }
    })
}
$jsonPath = Join-Path $outDir 'endpoint.json'
Write-AuditJsonFile -Path $jsonPath -InputObject $report

# Markdown
$sb = New-Object System.Text.StringBuilder
function A { param([string]$s) [void]$sb.AppendLine($s) }
A '# 端点排查报告'
A ''
A ("- 生成时间：{0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
A ("- 模式：{0}" -f $(if ($mode -eq 'file') { "离线文件分析" } else { "设备直连" }))
if ($deviceInfo) {
    A ("- 设备：{0} {1}（{2}）" -f $deviceInfo.manufacturer, $deviceInfo.model, $deviceInfo.serial)
}
A ("- 已安装应用：{0} 个" -f $packages.Count)
A ''
A '## 一、结论'
A ''
if ($ruleHits.Count -eq 0) {
    A '> **未发现回连运营商 DM 平台或已知可疑端点的迹象。**'
    A ''
    A '注意：非 root 设备通常读不到 netstat/DNS 缓存，本结论的边界是「未匹配到已知特征」。'
} else {
    A ("**发现 {0} 处需要关注的端点线索。**" -f $ruleHits.Count)
}
A ''
A '## 二、运营商 DM 平台域名命中'
A ''
if ($domainsFound.Count -eq 0) {
    A '_未在采集到的网络数据中发现运营商 DM 域名。_'
} else {
    A '| 域名 | 端口 | 原始匹配 |'
    A '| --- | --- | --- |'
    foreach ($d in $domainsFound) {
        A ("| {0} | {1} | {2} |" -f $d.Domain, $d.Port, $d.Match)
    }
}
A ''
A '## 三、包名 → 已知端点映射'
A ''
if ($mapped.Count -eq 0) {
    A '_没有应用匹配已知的「运营商 DM / 厂商上报组件」包名特征。_'
} else {
    A '| 包名 | 归属 | 已知端点 | 明文 HTTP | 说明 |'
    A '| --- | --- | --- | --- | --- |'
    foreach ($m in $mapped) {
        A ("| {0} | {1} | {2} | {3} | {4} |" -f `
            $m.Package, $m.Operator, (($m.Endpoints) -join '<br>'), `
            $(if ($m.PlainHttp) { '**是**' } else { '否' }), `
            ($m.Note -replace '\|', '\|'))
    }
}
A ''
A '## 四、规则命中明细'
A ''
if ($ruleHits.Count -eq 0) {
    A '_无_'
} else {
    A '| 规则 | 权重 | 域名/证据 | 相关包 |'
    A '| --- | --- | --- | --- |'
    foreach ($h in $ruleHits) {
        A ("| {0} {1} | {2} | {3} | {4} |" -f $h.Rule, $h.Name, $h.Weight, $h.Domain, (Get-AuditProp $h 'Package' '—'))
    }
    A ''
    A '**处置建议：**'
    $seenAdvice = @{}
    foreach ($h in $ruleHits) {
        if ($h.Advice -and -not $seenAdvice.ContainsKey($h.Advice)) {
            $seenAdvice[$h.Advice] = $true
            A ("- {0}" -f $h.Advice)
        }
    }
}
A ''
A '## 五、补充说明'
A ''
A '### 为什么「包名映射」也算证据'
A ''
A '小米样本 SystemHelper 的关键特征之一就是「插的是中国移动卡，却往中国联通 dm.wo.com.cn 注册」，'
A '这说明它是按运营商渠道定制分区预装的组件，而非通用系统组件。'
A '因此「包名特征 → 已知端点」的映射本身就构成高置信度线索，不必等抓包。'
A ''
A '### 想拿到确凿的实时连接，可选做法'
A ''
A '1. **root + tcpdump**：`adb shell tcpdump -i any -w /sdcard/cap.pcap`，再拉到电脑分析。'
A '2. **PC 端抓包**：手机连电脑热点，用 Wireshark 抓热点网卡，过滤 `dns` 看域名。'
A '3. **私有 DNS 日志**：手机上设置 → 网络 → 私人 DNS 填一个可记录日志的 DoH 服务。'
A '4. **hdc/开发者工具**：HarmonyOS NEXT 需用 hdc，且华为对 shell 权限限制很严。'
A ''
A ("_JSON：`{0}`_" -f $jsonPath)

$mdPath = Join-Path $outDir 'endpoint.md'
Write-AuditTextFile -Path $mdPath -Content $sb.ToString()

if ($JsonOnly) {
    [Console]::Out.Write((ConvertTo-AuditJsonLike -InputObject $report))
} else {
    Write-Host ''
    Write-AuditRule
    Write-Host '  端点排查完成' -ForegroundColor Green
    Write-AuditRule
    Write-Host ("  DM 域名命中      : {0}" -f $domainsFound.Count)
    Write-Host ("  包名映射命中     : {0}" -f $mapped.Count)
    Write-Host ("  规则命中         : {0}" -f $ruleHits.Count)
    if ($mapped.Count -gt 0 -or $ruleHits.Count -gt 0) {
        Write-Host ''
        Write-Host '  需要关注：' -ForegroundColor Yellow
        foreach ($m in $mapped) {
            Write-Host ("    - {0}  →  {1}" -f $m.Package, (($m.Endpoints) -join ', ')) -ForegroundColor Yellow
        }
    }
    Write-Host ''
    Write-Host ("  Markdown: {0}" -f $mdPath)
    Write-Host ("  JSON    : {0}" -f $jsonPath)
    Write-AuditRule
    Write-Host ''
}

exit 0
