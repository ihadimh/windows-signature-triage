<#
.SYNOPSIS
    安装 windows-signature-triage 技能到本机 DSH。

.DESCRIPTION
    默认装到 %USERPROFILE%\.dsh\skills\windows-signature-triage。
    优先用脚本所在目录的 SKILL.md；找不到再下载（带镜像回退）。

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -Dest "D:\myproject\.dsh\skills"
#>
param(
    [string]$Dest = "$env:USERPROFILE\.dsh\skills",
    [string]$Repo = "ihadimh/windows-signature-triage",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
$Name = "windows-signature-triage"
$Target = Join-Path (Join-Path $Dest $Name) "SKILL.md"

function Say($m)  { Write-Host "  $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  windows-signature-triage 安装器" -ForegroundColor White
Write-Host "  -------------------------------" -ForegroundColor DarkGray

New-Item -ItemType Directory -Force -Path (Join-Path $Dest $Name) | Out-Null
Say "目标：$Target"

# 1) 本地副本
$local = Join-Path $PSScriptRoot "SKILL.md"
if ($local -and (Test-Path $local)) {
    Copy-Item $local $Target -Force
    Ok "已从本地复制"
} else {
    # 2) 下载（带镜像回退）
    $urls = @(
        "https://raw.githubusercontent.com/$Repo/$Branch/SKILL.md",
        "https://ghproxy.net/https://raw.githubusercontent.com/$Repo/$Branch/SKILL.md",
        "https://raw.gitmirror.com/$Repo/$Branch/SKILL.md"
    )
    $done = $false
    foreach ($u in $urls) {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20
            if ($r.StatusCode -eq 200 -and $r.Content -match "^---") {
                # 必须写成“无 BOM 的 UTF-8”：带 BOM 时 SKILL.md 的 frontmatter
                # 会解析失败，技能会被静默丢弃（PS 5.1 的 -Encoding UTF8 会加 BOM）
                $text = ($r.Content -replace "`r`n", "`n")
                [System.IO.File]::WriteAllText($Target, $text, (New-Object System.Text.UTF8Encoding($false)))
                Ok "已下载"
                $done = $true
                break
            }
        } catch { Warn "下载失败，换下一个来源" }
    }
    if (-not $done) {
        Write-Host "  安装失败：既没有本地副本，也下载不到。" -ForegroundColor Red
        Write-Host "  可以手动 git clone 到：$Dest\$Name" -ForegroundColor Red
        exit 1
    }
}

# 简单校验 frontmatter
$head = Get-Content $Target -TotalCount 6 -Encoding UTF8
if (-not ($head -match "^name:\s*$Name")) {
    Warn "frontmatter 里没找到 name: $Name，可能不会被识别"
}

Write-Host ""
Ok "安装完成"
Write-Host "  重启 DSH 会话后生效，验证：问「你有哪些 skill」" -ForegroundColor Cyan
Write-Host ""
