<#
.SYNOPSIS
    安装自检：验证 SKILL.md 能不能被 DSH 真正加载。

.DESCRIPTION
    这个脚本存在的原因，是下面三类问题**都不会报错**，只会让技能静默消失：

      1. 文件带 UTF-8 BOM  -> frontmatter 解析失败
      2. frontmatter 的值里有「: 」 -> YAML 当成嵌套映射
      3. name 与安装目录名不一致 -> 扫描不到

    第 1、2 条都真的发生过一次。跑一遍这个脚本，比"重启会话看看还在不在"快。

.EXAMPLE
    .\verify-install.ps1

.EXAMPLE
    .\verify-install.ps1 -Dest "D:\proj\.dsh\skills"
#>
[CmdletBinding()]
param(
    [string]$Dest = (Join-Path $env:TEMP ("certdiag-verify-" + [guid]::NewGuid().ToString("N").Substring(0, 8)))
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src  = Join-Path $Root "SKILL.md"
$Name = "windows-signature-triage"

$fail = 0
function Ok($m)   { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  [!!]   $m" -ForegroundColor Red; $script:fail++ }
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  windows-signature-triage 安装自检" -ForegroundColor Cyan
Write-Host "  ---------------------------------" -ForegroundColor Cyan

# ---------- 1. 源文件 ----------
if (-not (Test-Path $Src)) {
    Bad "找不到 SKILL.md：$Src"
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($Src)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Bad "SKILL.md 带 UTF-8 BOM —— frontmatter 会解析失败（另存为 UTF-8 无 BOM）"
} else {
    Ok "无 BOM（$($bytes.Length) 字节）"
}

$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$lines = $text -split "`r?`n"

if ($lines[0].Trim() -ne "---") {
    Bad "第一行不是 ---：'$($lines[0])'"
} else {
    Ok "frontmatter 起始标记正确"
}

$close = -1
for ($i = 1; $i -lt [Math]::Min($lines.Count, 60); $i++) {
    if ($lines[$i].Trim() -eq "---") { $close = $i; break }
}
if ($close -lt 0) {
    Bad "找不到 frontmatter 结束标记 ---"
    exit 1
}

# ---------- 2. frontmatter 内容 ----------
$meta = @{}
$colonProblem = $false
for ($i = 1; $i -lt $close; $i++) {
    $ln = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    $idx = $ln.IndexOf(":")
    if ($idx -lt 1) { continue }
    $key = $ln.Substring(0, $idx).Trim()
    $val = $ln.Substring($idx + 1).Trim()
    $meta[$key] = $val
    if ($val.Contains(": ")) {
        Bad "字段 $key 的值里含「: 」—— YAML 会当成嵌套映射：$val"
        $colonProblem = $true
    }
}
if (-not $colonProblem) { Ok "frontmatter 无 YAML 冒号陷阱" }

foreach ($k in @("name", "description")) {
    if (-not $meta.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($meta[$k])) {
        Bad "缺少必填字段 $k"
    } else {
        Ok "字段 $k 存在"
    }
}

if ($meta.ContainsKey("name") -and $meta["name"] -ne $Name) {
    Bad "name（$($meta['name'])）与安装目录名（$Name）不一致，会被扫描跳过"
} else {
    Ok "name 与安装目录名一致"
}

if ($meta.ContainsKey("description") -and $meta["description"].Length -lt 20) {
    Bad "description 太短（$($meta['description'].Length) 字），不容易被正确触发"
} else {
    Ok "description 长度合理"
}

$body = ($lines[$close..($lines.Count - 1)] -join "`n").Trim()
if ($body.Length -lt 200) {
    Bad "正文过短（$($body.Length) 字符）"
} else {
    Ok "正文 $($lines.Count - $close - 1) 行"
}

# ---------- 3. 模拟安装 ----------
$targetDir = Join-Path $Dest $Name
$target = Join-Path $targetDir "SKILL.md"
try {
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item $Src $target -Force

    $b2 = [System.IO.File]::ReadAllBytes($target)
    if ($b2[0] -eq 0xEF -and $b2[1] -eq 0xBB -and $b2[2] -eq 0xBF) {
        Bad "安装后的文件带 BOM"
    } else {
        Ok "安装副本无 BOM"
    }

    $t2 = [System.Text.Encoding]::UTF8.GetString($b2)
    if ($t2.StartsWith("---")) { Ok "安装副本 frontmatter 可识别" } else { Bad "安装副本 frontmatter 异常" }
    Info "模拟安装位置：$targetDir"
} catch {
    Bad "模拟安装失败：$_"
}

# ---------- 4. 如果有安装器，跑一遍真实安装 ----------
$Installer = Join-Path $Root "install.ps1"
if (Test-Path $Installer) {
    $realDest = Join-Path $Dest "via-installer"
    try {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Installer -Dest $realDest 2>&1
        $code = $LASTEXITCODE
        $installed = Join-Path (Join-Path $realDest $Name) "SKILL.md"
        if ($code -eq 0 -and (Test-Path $installed)) {
            $b3 = [System.IO.File]::ReadAllBytes($installed)
            if ($b3[0] -eq 0xEF -and $b3[1] -eq 0xBB) {
                Bad "install.ps1 安装出的文件带 BOM"
            } else {
                Ok "install.ps1 端到端可用（退出码 $code）"
            }
        } else {
            Bad "install.ps1 失败（退出码 $code）：$($out | Select-Object -Last 1)"
        }
    } catch {
        Bad "install.ps1 无法运行：$_"
    }
} else {
    Info "未找到 install.ps1，跳过端到端安装测试"
}

# ---------- 清理 ----------
try {
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force -ErrorAction SilentlyContinue }
} catch { }

Write-Host ""
if ($fail -eq 0) {
    Write-Host "  全部通过：把 SKILL.md 放进 <技能目录>\windows-signature-triage\ 即可被加载" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  有 $fail 项未通过，修好后重跑" -ForegroundColor Red
    Write-Host "  提示：BOM 用「另存为 UTF-8 无 BOM」；冒号改成中文冒号或去掉" -ForegroundColor DarkGray
    exit 1
}
