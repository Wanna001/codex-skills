<#
.SYNOPSIS
    检查 / 修复 Windows 脚本文件的编码，避免中文（CJK）乱码。

    .DESCRIPTION
    按扩展名套用固定策略：
      .ps1 .psm1 .psd1                              -> 含非 ASCII 时 UTF-8 with BOM
                                                       （纯 ASCII 允许无 BOM；-StrictBom 可强制统一）
      .bat .cmd                                     -> CRLF；含非 ASCII 时 UTF-8(无 BOM)
                                                       且 chcp 65001 出现在任何非 ASCII 行之前
                                                       -BatchMode Ansi 时改写为系统 ANSI(936)
      .py .md .json .txt .csv .yaml .yml .xml .html -> UTF-8 无 BOM
    读取时自动识别 BOM / UTF-8 / ANSI(系统 ACP)。
    默认只检查、不修改；-Fix 才就地改写。

.PARAMETER BatchMode
    Utf8Chcp（默认）：批处理存为 UTF-8 无 BOM，并保证 chcp 65001 在任何非 ASCII 行之前。
    Ansi：批处理存为系统 ANSI 代码页（中文 Windows 为 936），适合只在中文 Windows 运行的旧脚本。

.PARAMETER SourceEncoding
    Auto（默认）自动判定源编码。个别 GBK 字节序列也能通过 UTF-8 校验时，用 Ansi 强制指定。

.PARAMETER StrictBom
    要求所有 .ps1/.psm1/.psd1 都带 BOM，即使内容全是 ASCII。默认只对含非 ASCII 的文件强制 BOM，
    避免给纯 ASCII 的老脚本刷出无意义的 diff。

.EXAMPLE
    pwsh -NoProfile -File normalize-script-encoding.ps1 -Path . -Recurse -Check

.EXAMPLE
    pwsh -NoProfile -File normalize-script-encoding.ps1 -Path .\scripts -Recurse -Fix
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [switch]$Recurse,

    [switch]$Fix,

    [switch]$Check,

    [ValidateSet('Auto', 'Utf8', 'Ansi')]
    [string]$SourceEncoding = 'Auto',

    [ValidateSet('Utf8Chcp', 'Ansi')]
    [string]$BatchMode = 'Utf8Chcp',

    [switch]$StrictBom
)

$ErrorActionPreference = 'Stop'

$script:checked = 0
$script:fixed = 0
$script:failed = 0

$utf8Bom    = [Text.UTF8Encoding]::new($true, $true)
$utf8NoBom  = [Text.UTF8Encoding]::new($false, $true)
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)

$ansiCodePage = 936
try {
    $acp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name ACP -ErrorAction Stop).ACP
    if ($acp) { $ansiCodePage = [int]$acp }
} catch {
    Write-Warning "无法读取系统 ACP，按 $ansiCodePage 处理 ANSI 文件"
}

$ansiEncoding = $null
try { $ansiEncoding = [Text.Encoding]::GetEncoding($ansiCodePage) }
catch { Write-Warning "无法加载 ANSI 代码页 $ansiCodePage，将无法读取/写出 ANSI 文件" }

$ansiLabel = "ANSI-$ansiCodePage"

$policy = @{
    '.ps1'  = 'UTF-8-BOM'
    '.psm1' = 'UTF-8-BOM'
    '.psd1' = 'UTF-8-BOM'
    '.bat'  = 'BATCH'
    '.cmd'  = 'BATCH'
    '.py'   = 'UTF-8'
    '.md'   = 'UTF-8'
    '.json' = 'UTF-8'
    '.txt'  = 'UTF-8'
    '.csv'  = 'UTF-8'
    '.yaml' = 'UTF-8'
    '.yml'  = 'UTF-8'
    '.xml'  = 'UTF-8'
    '.html' = 'UTF-8'
}

function Test-NonAscii {
    param([string]$Text)
    if ($null -eq $Text -or $Text.Length -eq 0) { return $false }
    return ($Text -match '[^\x00-\x7F]')
}

function Get-LineEnding {
    param([string]$Text)
    if ($null -eq $Text -or $Text.Length -eq 0) { return 'None' }
    $hasCrlf = $Text.Contains("`r`n")
    $hasLfOnly = $Text -match "(?<!`r)`n"
    $hasCrOnly = $Text -match "`r(?!`n)"
    if ($hasCrlf -and ($hasLfOnly -or $hasCrOnly)) { return 'Mixed' }
    if ($hasCrlf) { return 'CRLF' }
    if ($hasLfOnly) { return 'LF' }
    if ($hasCrOnly) { return 'CR' }
    return 'None'
}

function ConvertTo-Crlf {
    param([string]$Text)
    $t = $Text -replace "`r`n", "`n"
    $t = $t -replace "`r", "`n"
    $t = $t -replace "`n", "`r`n"
    return $t
}

function Get-ChcpLine {
    param([string]$Text, [string]$CodePage)
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ([regex]::IsMatch($lines[$i], '^\s*@?chcp\s+' + [regex]::Escape($CodePage) + '\b')) { return $i }
    }
    return -1
}

function Test-ChcpBeforeCjk {
    param([string]$Text, [string]$CodePage)
    $chcpLine = Get-ChcpLine -Text $Text -CodePage $CodePage
    if ($chcpLine -lt 0) { return $false }
    $cjkLine = Get-FirstCjkLine -Text $Text
    if ($cjkLine -lt 0) { return $true }
    return ($chcpLine -lt $cjkLine)
}

function Remove-ChcpLines {
    param([string]$Text, [string[]]$CodePages)
    $escaped = @($CodePages | ForEach-Object { [regex]::Escape($_) })
    $pattern = '^\s*@?chcp\s+(' + ($escaped -join '|') + ')\b'
    $lines = @($Text -split "`r?`n") | Where-Object { -not [regex]::IsMatch($_, $pattern) }
    return ($lines -join "`r`n")
}

function Add-ChcpLine {
    param([string]$Text, [string]$CodePage)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($Text -split "`r?`n")) { [void]$lines.Add($l) }
    $insertAt = 0
    if ($lines.Count -gt 0 -and $lines[0] -match '^\s*@?echo\s+off\s*$') { $insertAt = 1 }
    $lines.Insert($insertAt, 'chcp ' + $CodePage + '>nul')
    return ($lines -join "`r`n")
}

function Get-FirstCjkLine {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (Test-NonAscii $lines[$i]) { return $i }
    }
    return -1
}

function Read-SourceFile {
    param([string]$File)

    $bytes = [IO.File]::ReadAllBytes($File)
    $result = @{ Text = ''; Encoding = 'Unknown'; Bytes = $bytes }

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $result.Text = $utf8NoBom.GetString($bytes, 3, $bytes.Length - 3)
        $result.Encoding = 'UTF-8-BOM'
        return $result
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $result.Text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        $result.Encoding = 'UTF-16LE'
        return $result
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $result.Text = [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
        $result.Encoding = 'UTF-16BE'
        return $result
    }

    if ($SourceEncoding -eq 'Ansi') {
        if (-not $ansiEncoding) { $result.Encoding = 'Unknown'; return $result }
        $result.Text = $ansiEncoding.GetString($bytes)
        $result.Encoding = $ansiLabel
        return $result
    }

    $isUtf8 = $true
    try { [void]$strictUtf8.GetString($bytes) } catch { $isUtf8 = $false }

    if ($isUtf8 -or $SourceEncoding -eq 'Utf8') {
        $result.Text = $utf8NoBom.GetString($bytes)
        $result.Encoding = 'UTF-8'
        return $result
    }
    if ($ansiEncoding) {
        $result.Text = $ansiEncoding.GetString($bytes)
        $result.Encoding = $ansiLabel
        return $result
    }
    $result.Encoding = 'Unknown'
    return $result
}

function Save-TextFile {
    param([string]$File, [string]$Text, [string]$TargetEncoding)
    $enc = switch ($TargetEncoding) {
        'UTF-8-BOM' { $utf8Bom }
        'UTF-8'     { $utf8NoBom }
        default {
            if ($TargetEncoding -eq $ansiLabel) { $ansiEncoding } else { $utf8NoBom }
        }
    }
    if (-not $enc) { throw "无法解析目标编码 $TargetEncoding" }
    [IO.File]::WriteAllBytes($File, $enc.GetPreamble() + $enc.GetBytes($Text))
}

$files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($p in $Path) {
    $resolved = Get-ChildItem -Path $p -File -Recurse:$Recurse -ErrorAction SilentlyContinue
    if (-not $resolved) { $resolved = Get-Item -Path $p -File -ErrorAction SilentlyContinue }
    if (-not $resolved) {
        Write-Host "[ERROR] 路径不存在或无文件：$p"
        exit 2
    }
    foreach ($f in $resolved) {
        if (-not $files.Contains($f)) { [void]$files.Add($f) }
    }
}

foreach ($file in $files) {
    $ext = $file.Extension.ToLowerInvariant()
    if (-not $policy.ContainsKey($ext)) { continue }

    $script:checked++
    $src = Read-SourceFile -File $file.FullName
    $kind = $policy[$ext]
    $relative = $file.FullName

    if ($src.Encoding -eq 'Unknown') {
        Write-Host "[FAIL] $relative  无法判定编码（源编码未知，可试 -SourceEncoding Ansi）"
        $script:failed++
        continue
    }

    $target = $null
    $newText = $src.Text
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($kind -eq 'UTF-8-BOM') {
        $target = 'UTF-8-BOM'
        if ($src.Encoding -eq 'UTF-16LE' -or $src.Encoding -eq 'UTF-16BE') {
            $reasons.Add("UTF-16 需转为 $target")
        }
        elseif ($src.Encoding -ne $target) {
            if ($StrictBom -or (Test-NonAscii $src.Text)) {
                $reasons.Add("$($src.Encoding) 需转为 $target")
            }
        }
    }
    elseif ($kind -eq 'BATCH') {
        if ($src.Encoding -eq 'UTF-16LE' -or $src.Encoding -eq 'UTF-16BE') {
            $reasons.Add('批处理不支持 UTF-16，需转为 UTF-8 或 ANSI')
        }
        $eol = Get-LineEnding $src.Text
        if ($eol -ne 'CRLF' -and $eol -ne 'None') {
            $reasons.Add("行尾 $eol 需为 CRLF")
        }
        $newText = ConvertTo-Crlf $src.Text

        if ($BatchMode -eq 'Ansi') {
            $target = $ansiLabel
            if ($src.Encoding -ne $target) { $reasons.Add("$($src.Encoding) 需转为 $target") }
            if ((Test-NonAscii $src.Text) -and -not (Test-ChcpBeforeCjk -Text $newText -CodePage "$ansiCodePage")) {
                $reasons.Add("含非 ASCII 但缺少位于最前的 chcp $ansiCodePage")
            }
        }
        else {
            $target = 'UTF-8'
            if ($src.Encoding -ne $target) { $reasons.Add("$($src.Encoding) 需转为 $target") }
            if (Test-NonAscii $src.Text) {
                if (-not (Test-ChcpBeforeCjk -Text $newText -CodePage '65001')) {
                    $chcpLine = Get-ChcpLine -Text $newText -CodePage '65001'
                    if ($chcpLine -lt 0) {
                        $reasons.Add('含中文但缺少 chcp 65001')
                    }
                    else {
                        $reasons.Add('chcp 65001 位于首个中文行之后')
                    }
                }
            }
        }
    }
    else {
        $target = 'UTF-8'
        if ($src.Encoding -ne $target) { $reasons.Add("$($src.Encoding) 需转为 $target") }
    }

    if ($reasons.Count -eq 0) {
        Write-Verbose "[OK]   $relative  ($($src.Encoding))"
        continue
    }

    $detail = ($reasons -join '；')
    if (-not $Fix) {
        Write-Host "[FAIL] $relative  $detail"
        $script:failed++
        continue
    }

    try {
        if ($kind -eq 'BATCH' -and (Test-NonAscii $src.Text)) {
            if ($BatchMode -eq 'Utf8Chcp') {
                $newText = Remove-ChcpLines -Text $newText -CodePages @('65001')
                $newText = Add-ChcpLine -Text $newText -CodePage '65001'
            }
            else {
                $newText = Remove-ChcpLines -Text $newText -CodePages @('65001', "$ansiCodePage")
                $newText = Add-ChcpLine -Text $newText -CodePage "$ansiCodePage"
            }
        }
        Save-TextFile -File $file.FullName -Text $newText -TargetEncoding $target
        Write-Host "[FIXED] $relative  $($src.Encoding) -> $target  ($detail)"
        $script:fixed++
    } catch {
        Write-Host "[FAIL] $relative  写入失败：$($_.Exception.Message)"
        $script:failed++
    }
}

Write-Host ("checked={0} fixed={1} violations={2}" -f $script:checked, $script:fixed, $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
