# 确保所有 .ps1 都带 UTF-8 BOM（PS5.1 不加 BOM 会把中文按 GBK 解析导致假语法错）
param([string]$Root = 'D:\ChinaPhone\scripts')

$utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)
Get-ChildItem $Root -Filter '*.ps1' -Recurse | ForEach-Object {
    $p = $_.FullName
    $b = [System.IO.File]::ReadAllBytes($p)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        Write-Host ("OK    " + $_.Name)
    } else {
        [System.IO.File]::WriteAllBytes($p, ($utf8Bom + $b))
        Write-Host ("FIXED " + $_.Name)
    }
    # 顺带做语法检查
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$errs)
    if ($errs) {
        Write-Host ("  [!] " + $_.Name + " 有 " + $errs.Count + " 个语法错：") -ForegroundColor Red
        $errs | Select-Object -First 5 | ForEach-Object {
            Write-Host ("      L" + $_.Extent.StartLineNumber + ": " + $_.Message) -ForegroundColor Red
        }
    }
}
