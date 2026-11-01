# 自测：验证解析 + 打分 + 报告生成链路（不连设备）
$ErrorActionPreference = 'Stop'
# 用相对本脚本的路径，避免目录改名后失效
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $here 'DeviceAudit.Common.ps1')

$fail = 0
function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host ("  [PASS] " + $Name) -ForegroundColor Green }
    else { Write-Host ("  [FAIL] " + $Name + " " + $Detail) -ForegroundColor Red; $script:fail++ }
}

Write-Host '=== 1. 规则库加载 ==='
$rs = Get-AuditRules -RulesPath (Join-Path $here 'rules.json') -ScriptRoot $here
Check '规则数=13' ($rs.Rules.Count -eq 13) ("实际 " + $rs.Rules.Count)
Check '无警告' ($rs.Warnings.Count -eq 0) (($rs.Warnings) -join ';')

Write-Host ''
Write-Host '=== 2. 包名类规则匹配 ==='
$expect = @{
    'com.mobiletools.systemhelper' = 'R001'
    'com.miui.guardprovider'       = 'R002'
    'com.cucc.device.dm'           = 'R001'
    'com.tencent.mm'               = ''
}
foreach ($tp in $expect.Keys) {
    $hits = @()
    foreach ($r in $rs.Rules) {
        if ($r.Type -eq 'package_keyword' -and (Test-AuditRegex -Text $tp -Pattern ([string]$r.Match))) { $hits += $r.Id }
    }
    $got = ($hits -join ',')
    Check ("$tp -> '$($expect[$tp])'") ($got -eq $expect[$tp]) ("实际 '$got'")
}

Write-Host ''
Write-Host '=== 3. 分级函数 ==='
foreach ($pair in @(@(0,'低'), @(20,'低'), @(45,'中'), @(75,'高'), @(100,'高'))) {
    $lv = Get-AuditLevel -Score $pair[0] -Scoring $rs.Scoring
    Check ("分数 $($pair[0]) -> $($pair[1])") ($lv -eq $pair[1]) ("实际 $lv")
}

Write-Host ''
Write-Host '=== 4. JSON 生成 ==='
$tmpList = New-Object System.Collections.Generic.List[object]
$tmpList.Add([pscustomobject]@{ k = 'v' })
$obj = [ordered]@{
    tool = 'test'; nums = @(1,2,3)
    nested = [ordered]@{ a = 1; b = @('x','y') }
    empty = @(); list = $tmpList.ToArray()
    single = @('只有一项')
}
$json = ConvertTo-AuditJsonLike -InputObject $obj
try {
    $back = $json | ConvertFrom-Json
    Check 'JSON 可回环' ($back.tool -eq 'test')
    Check '单元素数组没被压成标量' ($back.single -is [System.Array] -and $back.single.Count -eq 1)
} catch { Check 'JSON 可回环' $false $_.Exception.Message }

Write-Host ''
Write-Host '=== 5. Markdown 表格 ==='
$tbl = Get-AuditMarkdownTable -Headers @('包名','评分','说明') -Rows @(
    ,@('com.miui.guardprovider', 95, '含竖线|测试')
    ,@('com.mobiletools.systemhelper', 90, '普通')
)
Write-Host $tbl
$tblLines = @($tbl -split "`r?`n" | Where-Object { $_ -match '^\|' })
Check '表格行数=4（表头+分隔+2行）' ($tblLines.Count -eq 4) ("实际 " + $tblLines.Count)
Check '第1行数据没被压扁' ($tblLines[2] -match 'com\.miui\.guardprovider') $tblLines[2]
Check '竖线被转义' ($tblLines[2] -match '\\\|') $tblLines[2]

Write-Host ''
Write-Host '=== 6. 导出组件状态机 ==='
$fake = @'
  Service #0 com.example/.RegisterHelperService
    ServiceType=0
    exported=true
    permission=null
  Service #1 com.example/.SafeService
    exported=true
    permission=android.permission.BIND_JOB_SERVICE
  Activity #2 com.example/.TestActivity
    exported=true
    permission=null
'@
$exportedFindings = New-Object System.Collections.Generic.List[object]
$curKind = ''; $curName = ''; $curExported = $false; $curPerm = ''
$pkgName = 'com.example'
$flushBlock = {
    param([string]$Kind, [string]$Name, [bool]$Exported, [string]$Perm, [string]$PkgName)
    if ($Kind -and $Name -and $Exported) {
        $exportedFindings.Add([pscustomobject]@{
            Package = $PkgName; Component = $Name; Kind = $Kind
            Protected = (-not [string]::IsNullOrWhiteSpace($Perm))
        })
    }
}
foreach ($ln in ($fake -split "`r?`n")) {
    $t = $ln.Trim()
    if ($t -match '^(Service|Activity) #\d+\s+([a-zA-Z0-9_.$\-/]+)') {
        $nm0 = $Matches[2]; if ($nm0 -match '^([^/]+)/\.(.+)$') { $nm0 = $Matches[1] + '.' + $Matches[2] }
        & $flushBlock $curKind $curName $curExported $curPerm $pkgName
        $curKind = $Matches[1]; $curName = $Matches[2]; $curExported = $false; $curPerm = ''
        continue
    }
    if (-not $curKind) { continue }
    if ($t -match '^exported=(true|false)') { if ($Matches[1] -eq 'true') { $curExported = $true }; continue }
    if ($t -match '^permission=(.+)$') {
        $pv = $Matches[1].Trim(); if ($pv -and $pv -ne 'null') { $curPerm = $pv }
        continue
    }
    if ($t -match '^(Provider|Receiver|Intent Filter|User \d+|Packages|Queries|Enabled)') {
        & $flushBlock $curKind $curName $curExported $curPerm $pkgName
        $curKind = ''; $curName = ''; $curExported = $false; $curPerm = ''
    }
}
& $flushBlock $curKind $curName $curExported $curPerm $pkgName
foreach ($f in $exportedFindings) {
    Write-Host ("  {0,-10} {1,-42} Protected={2}" -f $f.Kind, $f.Component, $f.Protected)
}
Check '抓到 3 个 exported 组件' ($exportedFindings.Count -eq 3) ("实际 " + $exportedFindings.Count)
$unprot = @($exportedFindings | Where-Object { -not $_.Protected })
Check '无保护的有 2 个' ($unprot.Count -eq 2) ("实际 " + $unprot.Count)
Check 'RegisterHelperService 被判为无保护' (@($unprot | Where-Object { $_.Component -match 'RegisterHelperService' }).Count -eq 1)
Check 'SafeService 被判为有保护' (@($exportedFindings | Where-Object { $_.Component -match 'SafeService' -and $_.Protected }).Count -eq 1)

Write-Host ''
Write-Host '=== 7. 权限组合匹配 ==='
$granted = @('android.permission.READ_PHONE_STATE', 'android.permission.QUERY_ALL_PACKAGES', 'android.permission.PACKAGE_USAGE_STATS')
$r004 = @($rs.Rules | Where-Object { $_.Id -eq 'R004' })[0]
$all = $true
foreach ($n in @($r004.Match)) {
    $hit = $false
    foreach ($g in $granted) { if ($g -like "*$n") { $hit = $true; break } }
    if (-not $hit) { $all = $false }
}
Check 'R004 三项权限齐备时命中' $all

Write-Host ''
if ($fail -eq 0) {
    Write-Host '全部自测通过' -ForegroundColor Green
    exit 0
} else {
    Write-Host ("有 $fail 项失败") -ForegroundColor Red
    exit 1
}
