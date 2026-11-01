<#
.SYNOPSIS
    国产 ROM 隐蔽上报组件审计工具 —— 主脚本。
.DESCRIPTION
    通过 adb 采集已安装应用清单、关键权限、导出面组件、常驻闹钟/服务，
    按 rules.json 规则库打分，输出 JSON（机器可读）+ Markdown（人可读）报告。
    对齐图中 NOIR 工具的思路：读应用清单 + 权限 + 网络端点 → 分类 → 风险分级 → 可执行建议。

    判据来源：2026-11 小米 HyperOS 实测样本
      - 「系统安全组件」= com.miui.guardprovider
      - 「SystemHelper」  = com.mobiletools.systemhelper（/system/priv-app/，回连联通 DM 平台明文 HTTP，
        采集 IMEI/IMSI/ICCID + 应用列表 + 后台定位，双 ELAPSED_WAKEUP 闹钟常驻，另有录屏云检测）

.PARAMETER OutputRoot
    报告根目录，默认 <工作区>\reports。
.PARAMETER Serial
    多设备时指定目标设备。
.PARAMETER RulesPath
    规则库路径，默认同目录 rules.json。
.PARAMETER JsonOnly
    只向 stdout 输出 JSON（日志转到 stderr），便于管道处理。
.PARAMETER SkipAlarm
    跳过 dumpsys alarm（该命令在部分 ROM 上很慢）。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\audit_android.ps1
.EXAMPLE
    .\audit_android.ps1 -Serial ABC123 -OutputRoot D:\ChinaPhone\reports
.NOTES
    兼容 Windows PowerShell 5.1 与 PowerShell 7+。
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [string]$Serial = '',
    [string]$RulesPath = '',
    [string]$AdbPath = '',
    [switch]$JsonOnly,
    [switch]$SkipAlarm,
    [switch]$NoScore
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0

# ---------------------------------------------------------------------------
# 引入公共库
# ---------------------------------------------------------------------------
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
# 工作区 / 输出目录
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $wsRoot = Get-AuditWorkspaceRoot -From $scriptRoot
    $OutputRoot = Join-Path $wsRoot 'reports'
}
$stamp = New-AuditTimestamp
$outDir = Join-Path $OutputRoot $stamp
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Log "审计开始 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'step'
Log "报告目录: $outDir"

# ---------------------------------------------------------------------------
# 定位 adb 与设备
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($AdbPath)) { $AdbPath = Find-AuditAdb }
$dev = Resolve-AuditDevice -AdbPath $AdbPath -Serial $Serial -AutoStart

if ($dev.Status -ne 'ok') {
    # 组装「无法继续」的结构化结果
    $fail = [ordered]@{
        tool        = 'ChinaPhone DeviceAudit'
        version     = '1.0.0'
        timestamp   = (Get-Date).ToString('o')
        status      = 'aborted'
        reason      = $dev.Status
        message     = $dev.Message
        suggestions = @($dev.Suggestions)
        adbPath     = [string]$AdbPath
        rules       = $null
    }
    if ($JsonOnly) {
        [Console]::Out.Write((ConvertTo-AuditJsonLike -InputObject $fail))
    } else {
        Write-Host ''
        Write-AuditRule
        Write-Host '  无法继续：' -ForegroundColor Yellow -NoNewline
        Write-Host $dev.Message -ForegroundColor White
        Write-AuditRule
        if ($dev.Suggestions -and $dev.Suggestions.Count -gt 0) {
            Write-Host ''
            Write-Host '  请按以下步骤处理：' -ForegroundColor Cyan
            $i = 0
            foreach ($s in $dev.Suggestions) {
                $i++
                Write-Host ("    {0}. {1}" -f $i, $s)
            }
        }
        Write-Host ''
        Write-Host ("  详细说明见: " + (Join-Path $scriptRoot 'README.md')) -ForegroundColor DarkGray
        Write-AuditRule
    }
    exit 1
}

$targetSerial = $dev.Serial
Log "目标设备: $targetSerial" 'ok'

# ---------------------------------------------------------------------------
# 采集：设备信息
# ---------------------------------------------------------------------------
function Get-Prop {
    param([string]$Key)
    $r = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @("getprop $Key") -TimeoutSeconds 20
    if ($r.Ok) { return (ConvertTo-AuditCleanString $r.StdOut).Trim() }
    return ''
}

Log '采集设备信息...' 'step'
$deviceInfo = [ordered]@{
    serial         = $targetSerial
    manufacturer   = (Get-Prop 'ro.product.manufacturer')
    brand          = (Get-Prop 'ro.product.brand')
    model          = (Get-Prop 'ro.product.model')
    device         = (Get-Prop 'ro.product.device')
    product        = (Get-Prop 'ro.product.name')
    androidVersion = (Get-Prop 'ro.build.version.release')
    sdk            = (Get-Prop 'ro.build.version.sdk')
    buildId        = (Get-Prop 'ro.build.display.id')
    buildType      = (Get-Prop 'ro.build.type')
    buildTags      = (Get-Prop 'ro.build.tags')
    securityPatch  = (Get-Prop 'ro.build.version.security_patch')
    romName        = (Get-Prop 'ro.build.version.incremental')
    miuiVersion    = (Get-Prop 'ro.miui.ui.version.name')
    emuiVersion    = (Get-Prop 'ro.build.version.emui')
    harmonyVersion = (Get-Prop 'hw_sc.build.platform.version')
}
$deviceInfo.rom = if ($deviceInfo.miuiVersion) { "MIUI/HyperOS $($deviceInfo.miuiVersion)" }
                  elseif ($deviceInfo.harmonyVersion) { "HarmonyOS $($deviceInfo.harmonyVersion)" }
                  elseif ($deviceInfo.emuiVersion) { "EMUI $($deviceInfo.emuiVersion)" }
                  else { '' }

Log ("  {0} {1} / Android {2} (SDK {3})" -f $deviceInfo.manufacturer, $deviceInfo.model, $deviceInfo.androidVersion, $deviceInfo.sdk) 'ok'

# ---------------------------------------------------------------------------
# 采集：已安装应用（含 APK 路径）
# ---------------------------------------------------------------------------
Log '采集已安装应用清单...' 'step'
$pkgResult = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('pm list packages -f') -TimeoutSeconds 90
$packages = New-Object System.Collections.Generic.List[object]
if ($pkgResult.Ok) {
    foreach ($line in ($pkgResult.StdOut -split "`r?`n")) {
        $t = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -notmatch '^package:') { continue }
        $body = $t.Substring(8)
        $eq = $body.LastIndexOf('=')
        if ($eq -lt 0) { continue }
        $apkPath = $body.Substring(0, $eq)
        $pkgName = $body.Substring($eq + 1)
        $inPrivApp = $false
        $inSystem = $false
        if ($apkPath -match '/priv-app/') { $inPrivApp = $true; $inSystem = $true }
        elseif ($apkPath -match '^/(system|system_ext|product|vendor|odm|my_product|my_stock|my_heytap)/') { $inSystem = $true }
        $packages.Add([pscustomobject]@{
            Name      = $pkgName
            ApkPath   = $apkPath
            InPrivApp = $inPrivApp
            InSystem  = $inSystem
        })
    }
}
Log ("  共 {0} 个应用，其中 priv-app {1} 个" -f $packages.Count, (@($packages | Where-Object { $_.InPrivApp }).Count)) 'ok'

# ---------------------------------------------------------------------------
# 采集：权限（只对候选包做 dumpsys，避免全量太慢）
# ---------------------------------------------------------------------------
Log '加载规则库...' 'step'
$ruleSet = Get-AuditRules -RulesPath $RulesPath -ScriptRoot $scriptRoot
if ($ruleSet.Warnings -and $ruleSet.Warnings.Count -gt 0) {
    foreach ($w in $ruleSet.Warnings) { Log $w 'warn' }
}
Log ("  规则 {0} 条，版本 {1}" -f $ruleSet.Rules.Count, $ruleSet.Meta.version) 'ok'

# 先用「包名类规则 + priv-app」筛出候选，再做 dumpsys 深度采集
$candidates = New-Object System.Collections.Generic.List[object]
foreach ($p in $packages) {
    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($rule in $ruleSet.Rules) {
        if ($rule.Type -eq 'package_keyword') {
            if (Test-AuditRegex -Text $p.Name -Pattern ([string]$rule.Match)) {
                $hits.Add([pscustomobject]@{ Rule = $rule; Evidence = "包名 $($p.Name) 命中模式" })
            }
        } elseif ($rule.Type -eq 'privapp') {
            if ($p.InPrivApp) {
                $hits.Add([pscustomobject]@{ Rule = $rule; Evidence = "APK 位于 $($p.ApkPath)" })
            }
        }
    }
    if ($hits.Count -gt 0) {
        # 娉ㄦ剰锛歅S 5.1 閲屽 List[object] 鐢?@(...) 浼氭姏銆屽弬鏁扮被鍨嬩笉鍖归厤銆嶏紝
        # 鍥犳杩欓噷淇濇寔 List 鏈韩锛堝彲鍙橈紝鍚庣画杩樿 .Add锛夛紝杈撳嚭鏃跺啀杞暟缁勩€?        $candidates.Add([pscustomobject]@{ Package = $p; Hits = $hits })
    }
}
Log ("  初筛候选 {0} 个（包名/priv-app 命中）" -f $candidates.Count) 'step'

# 对候选做 dumpsys package，抓权限与导出组件
$exportedFindings = New-Object System.Collections.Generic.List[object]
$alarmFindings = New-Object System.Collections.Generic.List[object]

$i = 0
foreach ($cand in $candidates) {
    $i++
    $pkg = $cand.Package
    $pct = [int](($i / [Math]::Max(1, $candidates.Count)) * 100)
    Log ("  [{0}/{1}] 深度采集 {2}" -f $i, $candidates.Count, $pkg.Name) 'info'

    $dump = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @("dumpsys package $($pkg.Name)") -TimeoutSeconds 45
    $raw = ''
    if ($dump.Ok) { $raw = ConvertTo-AuditCleanString $dump.StdOut }

    $granted = New-Object System.Collections.Generic.List[string]
    $requested = New-Object System.Collections.Generic.List[string]
    if ($raw) {
        foreach ($m in [regex]::Matches($raw, '(?m)^\s*([a-zA-Z0-9_.]+): granted=true')) {
            $granted.Add($m.Groups[1].Value)
        }
        foreach ($m in [regex]::Matches($raw, '(?m)^\s*(android\.permission\.[A-Z_0-9]+)\s*$')) {
            $requested.Add($m.Groups[1].Value)
        }
        # dangerous 段与 requested permissions 段都收一遍
        foreach ($m in [regex]::Matches($raw, '([a-zA-Z0-9_.]+): granted=true')) {
            if (-not $granted.Contains($m.Groups[1].Value)) { $granted.Add($m.Groups[1].Value) }
        }
        # 导出组件（exported=true 且没有 permission= 保护的 Service/Activity）
        # 用逐行状态机而不是跨行正则：dumpsys 的块嵌套很深，多行正则极易吃错块。
        # 注意：不能用「循环外定义的 scriptblock」当 flush —— 它看不到循环内更新的变量
        #（PS 的 scriptblock 在 dot-source 时按自身作用域解析变量），必须用函数显式传参。
        $curKind = ''
        $curName = ''
        $curExported = $false
        $curPerm = ''
        $pkgName = $pkg.Name
        $flushBlock = {
            param([string]$Kind, [string]$Name, [bool]$Exported, [string]$Perm, [string]$PkgName)
            if ($Kind -and $Name -and $Exported) {
                $exportedFindings.Add([pscustomobject]@{
                    Package   = $PkgName
                    Component = $Name
                    Kind      = $Kind
                    Protected = (-not [string]::IsNullOrWhiteSpace($Perm))
                })
            }
        }
        foreach ($ln in ($raw -split "`r?`n")) {
            $t = $ln.Trim()
            # 块头形如：  Service #3 com.foo.BarService  或  Service #3 com.foo/.BarService
            if ($t -match '^(Service|Activity) #\d+\s+([a-zA-Z0-9_.$\-/]+)') {
                & $flushBlock $curKind $curName $curExported $curPerm $pkgName
                $curKind = $Matches[1]
                # dumpsys 里简写形式是 "pkg/.Cls"，统一展开成 "pkg.Cls"
                $nm = $Matches[2]
                if ($nm -match '^([^/]+)/\.(.+)$') { $nm = $Matches[1] + '.' + $Matches[2] }
                $curName = $nm
                $curExported = $false
                $curPerm = ''
                continue
            }
            if (-not $curKind) { continue }
            if ($t -match '^exported=(true|false)') {
                if ($Matches[1] -eq 'true') { $curExported = $true }
                continue
            }
            if ($t -match '^permission=(.+)$') {
                $pv = $Matches[1].Trim()
                if ($pv -and $pv -ne 'null') { $curPerm = $pv }
                continue
            }
            # 遇到下一个互斥段落就结束当前块
            if ($t -match '^(Provider|Receiver|Intent Filter|User \d+|Packages|Queries|Enabled)') {
                & $flushBlock $curKind $curName $curExported $curPerm $pkgName
                $curKind = ''; $curName = ''; $curExported = $false; $curPerm = ''
                continue
            }
        }
        & $flushBlock $curKind $curName $curExported $curPerm $pkgName
    }

    # 权限类规则
    foreach ($rule in $ruleSet.Rules) {
        if ($rule.Type -eq 'permission_combo') {
            $need = @($rule.Match)
            $all = $true
            $missing = @()
            foreach ($n in $need) {
                $hit = $false
                foreach ($g in $granted) { if ($g -like "*$n") { $hit = $true; break } }
                if (-not $hit) {
                    foreach ($rq in $requested) { if ($rq -like "*$n") { $hit = $true; break } }
                }
                if (-not $hit) { $all = $false; $missing += $n }
            }
            if ($all) {
                $cand.Hits.Add([pscustomobject]@{
                    Rule = $rule
                    Evidence = ("权限组合齐备: " + ($need -join ' + '))
                })
            }
        } elseif ($rule.Type -eq 'permission_keyword') {
            foreach ($g in $granted) {
                if (Test-AuditRegex -Text $g -Pattern ([string]$rule.Match)) {
                    $cand.Hits.Add([pscustomobject]@{ Rule = $rule; Evidence = "授予权限 $g" })
                    break
                }
            }
        }
    }

    $cand | Add-Member -NotePropertyName GrantedPermissions -NotePropertyValue $granted.ToArray() -Force
    $cand | Add-Member -NotePropertyName ExportedComponents -NotePropertyValue @($exportedFindings | Where-Object { $_.Package -eq $pkg.Name }) -Force
}

# 导出面规则
foreach ($rule in $ruleSet.Rules) {
    if ($rule.Type -eq 'exported_component') {
        $unprotected = @($exportedFindings | Where-Object { -not $_.Protected })
        if ($unprotected.Count -gt 0) {
            # 归到对应候选包的命中里
            foreach ($cand in $candidates) {
                $mine = @($unprotected | Where-Object { $_.Package -eq $cand.Package.Name })
                if ($mine.Count -gt 0) {
                    $ev = ($mine | ForEach-Object { "$($_.Kind) $($_.Component)" }) -join '; '
                    $cand.Hits.Add([pscustomobject]@{ Rule = $rule; Evidence = "无权限保护导出: $ev" })
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 采集：闹钟常驻
# ---------------------------------------------------------------------------
if (-not $SkipAlarm) {
    Log '采集闹钟调度（dumpsys alarm，可能较慢）...' 'step'
    $alarm = Invoke-AdbShell -AdbPath $AdbPath -Serial $targetSerial -RemoteCommand @('dumpsys alarm') -TimeoutSeconds 120
    if ($alarm.Ok) {
        $araw = ConvertTo-AuditCleanString $alarm.StdOut
        $curPkg = ''
        foreach ($line in ($araw -split "`r?`n")) {
            $t = $line.TrimEnd()
            if ($t -match '^\s*(RTC|ELAPSED)_WAKEUP.*when=|^\s*\*\*\*.*$') { continue }
            if ($t -match '^\s*(\d+)?\s*([a-zA-Z0-9_.]+):\s*$') {
                $curPkg = $Matches[2]; continue
            }
            if ($t -match 'ELAPSED_WAKEUP' -and $curPkg) {
                $alarmFindings.Add([pscustomobject]@{ Package = $curPkg; Line = $t.Trim() })
            }
        }
        # 统计每个包的 ELAPSED_WAKEUP 条数
        $grouped = $alarmFindings | Group-Object -Property Package
        foreach ($g in @($grouped)) {
            if ($g.Count -ge 2) {
                foreach ($cand in $candidates) {
                    if ($cand.Package.Name -eq $g.Name) {
                        foreach ($rule in $ruleSet.Rules) {
                            if ($rule.Type -eq 'alarm_pattern') {
                                $cand.Hits.Add([pscustomobject]@{
                                    Rule = $rule
                                    Evidence = ("{0} 个 ELAPSED_WAKEUP 闹钟常驻" -f $g.Count)
                                })
                            }
                        }
                    }
                }
            }
        }
        Log ("  命中 ELAPSED_WAKEUP 的应用 {0} 个" -f @($alarmFindings | Select-Object -ExpandProperty Package -Unique).Count) 'ok'
    } else {
        Log '  dumpsys alarm 采集失败，跳过' 'warn'
    }
} else {
    Log '已按 -SkipAlarm 跳过闹钟采集' 'warn'
}

# ---------------------------------------------------------------------------
# 打分
# ---------------------------------------------------------------------------
Log '计算风险评分...' 'step'
$scoring = $ruleSet.Scoring
$results = New-Object System.Collections.Generic.List[object]
foreach ($cand in $candidates) {
    if ($NoScore) { break }
    $score = 0.0
    $seen = @{}
    $hitOut = New-Object System.Collections.Generic.List[object]
    foreach ($h in $cand.Hits) {
        $id = $h.Rule.Id
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $score += [double]$h.Rule.Weight
        $hitOut.Add([ordered]@{
            id       = $h.Rule.Id
            name     = $h.Rule.Name
            weight   = [double]$h.Rule.Weight
            type     = $h.Rule.Type
            evidence = $h.Evidence
            description = $h.Rule.Description
            advice   = $h.Rule.Advice
        })
    }
    if ($score -gt 100) { $score = 100 }
    $lvl = Get-AuditLevel -Score $score -Scoring $scoring
    $results.Add([pscustomobject]@{
        Package     = $cand.Package
        Score       = [Math]::Round($score, 1)
        Level       = $lvl
        Hits        = $hitOut.ToArray()
        Granted     = @($cand.GrantedPermissions)
        Exported    = @($cand.ExportedComponents)
    })
}
$sorted = @($results | Sort-Object -Property Score -Descending)

$high = @($sorted | Where-Object { $_.Level -eq '高' })
$medium = @($sorted | Where-Object { $_.Level -eq '中' })
$low = @($sorted | Where-Object { $_.Level -eq '低' })

Log ("  高风险 {0} 个 / 中风险 {1} 个 / 低风险 {2} 个" -f $high.Count, $medium.Count, $low.Count) 'ok'

# ---------------------------------------------------------------------------
# 输出 JSON
# ---------------------------------------------------------------------------
$report = [ordered]@{
    tool        = 'ChinaPhone DeviceAudit'
    version     = '1.0.0'
    timestamp   = (Get-Date).ToString('o')
    status      = 'ok'
    device      = $deviceInfo
    rules       = $ruleSet.Meta
    stats       = [ordered]@{
        totalPackages = $packages.Count
        privApps      = @($packages | Where-Object { $_.InPrivApp }).Count
        candidates    = $candidates.Count
        high          = $high.Count
        medium        = $medium.Count
        low           = $low.Count
    }
    findings    = @($sorted | ForEach-Object {
        [ordered]@{
            package  = $_.Package.Name
            apkPath  = $_.Package.ApkPath
            privApp  = $_.Package.InPrivApp
            systemApp= $_.Package.InSystem
            score    = $_.Score
            level    = $_.Level
            hits     = @($_.Hits)
        }
    })
}
$jsonPath = Join-Path $outDir 'audit.json'
Write-AuditJsonFile -Path $jsonPath -InputObject $report
Log "已写出 $jsonPath" 'ok'

# ---------------------------------------------------------------------------
# 输出 Markdown
# ---------------------------------------------------------------------------
Log '生成 Markdown 报告...' 'step'
$sb = New-Object System.Text.StringBuilder
function A { param([string]$s) [void]$sb.AppendLine($s) }

A '# 手机隐蔽上报组件审计报告'
A ''
A ("- 生成时间：{0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
A ("- 工具版本：ChinaPhone DeviceAudit 1.0.0")
A ("- 规则库：{0}（{1} 条规则）" -f $ruleSet.Meta.version, $ruleSet.Rules.Count)
A ''
A '## 一、设备信息'
A ''
A (Get-AuditMarkdownTable -Headers @('项目','值') -Rows @(
    ,@('厂商', $deviceInfo.manufacturer)
    ,@('品牌', $deviceInfo.brand)
    ,@('型号', $deviceInfo.model)
    ,@('系统版本', $deviceInfo.androidVersion)
    ,@('SDK', $deviceInfo.sdk)
    ,@('ROM', $deviceInfo.rom)
    ,@('构建号', $deviceInfo.buildId)
    ,@('安全补丁', $deviceInfo.securityPatch)
    ,@('Serial', $deviceInfo.serial)
))
A ''
A '## 二、总览'
A ''
A (Get-AuditMarkdownTable -Headers @('指标','数值') -Rows @(
    ,@('已安装应用总数', $packages.Count)
    ,@('priv-app 数量', @($packages | Where-Object { $_.InPrivApp }).Count)
    ,@('初筛候选', $candidates.Count)
    ,@('🔴 高风险', $high.Count)
    ,@('🟠 中风险', $medium.Count)
    ,@('🟢 低风险', $low.Count)
))
A ''
if ($high.Count -eq 0 -and $medium.Count -eq 0) {
    A '> **结论：未发现明显可疑的隐蔽上报组件。**'
    A '> 但这不代表绝对安全——规则库是启发式的，仅覆盖已知特征。'
} else {
    A '> **结论：发现需要关注的组件，详见下方明细。**'
}
A ''
A '## 三、高风险组件'
A ''
if ($high.Count -eq 0) {
    A '_无_'
} else {
    foreach ($f in $high) {
        A ("### 🔴 {0}  —— 评分 {1}" -f $f.Package.Name, $f.Score)
        A ''
        A ('- APK 路径：' + $f.Package.ApkPath)
        A ("- priv-app：{0} / 系统应用：{1}" -f $f.Package.InPrivApp, $f.Package.InSystem)
        A ''
        A '| 规则 | 权重 | 证据 |'
        A '| --- | --- | --- |'
        foreach ($h in $f.Hits) {
            A ("| {0} {1} | {2} | {3} |" -f $h.id, $h.name, $h.weight, ($h.evidence -replace '\|','\|'))
        }
        A ''
        $adv = @($f.Hits | Where-Object { $_.advice } | ForEach-Object { $_.advice }) | Select-Object -Unique
        if ($adv.Count -gt 0) {
            A '**处置建议：**'
            foreach ($a in $adv) { A ("- {0}" -f $a) }
            A ''
        }
    }
}
A '## 四、中风险组件'
A ''
if ($medium.Count -eq 0) { A '_无_' } else {
    A '| 包名 | 评分 | priv-app | 命中规则 |'
    A '| --- | --- | --- | --- |'
    foreach ($f in $medium) {
        $ids = (@($f.Hits | ForEach-Object { $_.id }) -join ', ')
        A ("| {0} | {1} | {2} | {3} |" -f $f.Package.Name, $f.Score, $f.Package.InPrivApp, $ids)
    }
}
A ''
A '## 五、低风险组件'
A ''
if ($low.Count -eq 0) { A '_无_' } else {
    A '| 包名 | 评分 | 命中规则 |'
    A '| --- | --- | --- |'
    foreach ($f in $low) {
        $ids = (@($f.Hits | ForEach-Object { $_.id }) -join ', ')
        A ("| {0} | {1} | {2} |" -f $f.Package.Name, $f.Score, $ids)
    }
}
A ''
A '## 六、导出的组件（无权限保护）'
A ''
$unprot = @($exportedFindings | Where-Object { -not $_.Protected })
if ($unprot.Count -eq 0) {
    A '_未发现无权限保护的导出组件。_'
} else {
    A '> 这些组件任意第三方应用可 bind/拉起，是本地提权与横向利用的入口。'
    A ''
    A '| 包名 | 类型 | 组件 |'
    A '| --- | --- | --- |'
    foreach ($c in $unprot) {
        A ("| {0} | {1} | {2} |" -f $c.Package, $c.Kind, $c.Component)
    }
}
A ''
A '## 七、判定说明（规则库口径）'
A ''
A '| 规则 ID | 名称 | 权重 | 说明 |'
A '| --- | --- | --- | --- |'
foreach ($r in $ruleSet.Rules) {
    A ("| {0} | {1} | {2} | {3} |" -f $r.Id, $r.Name, $r.Weight, (($r.Description -replace '\|','\|') -replace "`n", ' '))
}
A ''
A '## 八、如何处置（按风险从高到低）'
A ''
A '1. **先备份**：`adb shell pm list packages -f > packages-backup.txt`'
A '2. **停用（可回滚，推荐）**：`adb shell pm disable-user --user 0 <包名>`'
A '   - 回滚：`adb shell pm enable <包名>`'
A '3. **卸载用户态应用**：`adb shell pm uninstall --user 0 <包名>`（系统分区原件仍在，可恢复）'
A '4. **禁止 root 删除系统分区文件**——会导致 OTA 失败、系统异常。'
A '5. **网络层验证**：配合 `endpoint_check.ps1` 观察这些包有无回连运营商 DM 平台。'
A ''
A '## 九、免责声明'
A ''
A '本报告基于静态权限/组件特征做启发式判断，**不能证明**某组件确有恶意行为。'
A '命中规则只是「需要进一步确认」的信号，请结合厂商公开说明判断。'
A ''
A ("_报告文件：`{0}`_" -f $jsonPath)

$mdPath = Join-Path $outDir 'report.md'
Write-AuditTextFile -Path $mdPath -Content $sb.ToString()
Log "已写出 $mdPath" 'ok'

# ---------------------------------------------------------------------------
# 收尾输出
# ---------------------------------------------------------------------------
if ($JsonOnly) {
    [Console]::Out.Write((ConvertTo-AuditJsonLike -InputObject $report))
} else {
    Write-Host ''
    Write-AuditRule
    Write-Host '  审计完成' -ForegroundColor Green
    Write-AuditRule
    Write-Host ("  设备    : {0} {1} (Android {2})" -f $deviceInfo.manufacturer, $deviceInfo.model, $deviceInfo.androidVersion)
    Write-Host ("  应用总数: {0}（priv-app {1}）" -f $packages.Count, @($packages | Where-Object { $_.InPrivApp }).Count)
    Write-Host ''
    Write-Host ("  高风险 : {0}" -f $high.Count) -ForegroundColor Red
    Write-Host ("  中风险 : {0}" -f $medium.Count) -ForegroundColor Yellow
    Write-Host ("  低风险 : {0}" -f $low.Count) -ForegroundColor Green
    if ($high.Count -gt 0) {
        Write-Host ''
        Write-Host '  高风险包名：' -ForegroundColor Red
        foreach ($f in $high) {
            Write-Host ("    - {0}  (评分 {1})" -f $f.Package.Name, $f.Score) -ForegroundColor Red
        }
    }
    Write-Host ''
    Write-Host ("  Markdown 报告: {0}" -f $mdPath)
    Write-Host ("  JSON   报告: {0}" -f $jsonPath)
    Write-AuditRule
    Write-Host ''
}

exit 0
