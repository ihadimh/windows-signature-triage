<#
.SYNOPSIS
    安装 dsh-skills 里的技能到本机 DSH 技能目录。

.DESCRIPTION
    默认装到 %USERPROFILE%\.dsh\skills。
    支持三种来源，按顺序自动选择：
      1. 本地已有的仓库副本（脚本所在目录）
      2. git clone（需要 git）
      3. 直接下载 SKILL.md（GitHub 直连不稳时有镜像回退）

.EXAMPLE
    irm https://raw.githubusercontent.com/ihadimh/dsh-skills/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Skill windows-signature-triage
#>
param(
    [string]$Skill = "all",
    [string]$Dest = "$env:USERPROFILE\.dsh\skills",
    [string]$Repo = "ihadimh/dsh-skills"
)

$ErrorActionPreference = "Stop"
$Branch = "main"

function Write-Step($msg) { Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "  [!!] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  dsh-skills 安装器" -ForegroundColor White
Write-Host "  ------------------------" -ForegroundColor DarkGray

# 1) 目标目录
if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    Write-Step "已创建 $Dest"
}
Write-Step "目标目录：$Dest"

# 2) 决定要装哪些技能
$localRoot = $PSScriptRoot
if (-not $localRoot) { $localRoot = (Get-Location).Path }

$localSkills = @()
if (Test-Path $localRoot) {
    $localSkills = Get-ChildItem -Path $localRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } |
        Select-Object -ExpandProperty Name
}

if ($Skill -ne "all") {
    $targets = @($Skill)
} elseif ($localSkills.Count -gt 0) {
    $targets = $localSkills
} else {
    # 远程模式：按仓库目录列表安装
    $targets = @("windows-signature-triage")
}

Write-Step ("待安装：" + ($targets -join ", "))

$installed = @()
foreach ($name in $targets) {
    $destDir = Join-Path $Dest $name
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $srcFile = Join-Path $localRoot (Join-Path $name "SKILL.md")
    if (Test-Path $srcFile) {
        Copy-Item $srcFile (Join-Path $destDir "SKILL.md") -Force
        Write-Ok "$name（本地复制）"
        $installed += $name
        continue
    }

    $urls = @(
        "https://raw.githubusercontent.com/$Repo/$Branch/$name/SKILL.md",
        "https://ghproxy.net/https://raw.githubusercontent.com/$Repo/$Branch/$name/SKILL.md",
        "https://raw.gitmirror.com/$Repo/$Branch/$name/SKILL.md"
    )
    $done = $false
    foreach ($u in $urls) {
        try {
            $resp = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20
            if ($resp.StatusCode -eq 200 -and $resp.Content -match "^---") {
                Set-Content -Path (Join-Path $destDir "SKILL.md") -Value $resp.Content -Encoding UTF8
                Write-Ok "$name（下载成功）"
                $installed += $name
                $done = $true
                break
            }
        } catch {
            Write-Warn2 "下载失败，换下一个来源：$u"
        }
    }
    if (-not $done) { Write-Warn2 "$name 安装失败" }
}

Write-Host ""
if ($installed.Count -gt 0) {
    Write-Host "  已安装 $($installed.Count) 个技能：" -ForegroundColor Green
    $installed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Green }
    Write-Host ""
    Write-Host "  重启 DSH 会话后生效。" -ForegroundColor Cyan
    Write-Host "  验证：在新会话里问「你有哪些 skill」" -ForegroundColor Cyan
} else {
    Write-Host "  没有安装任何技能，请检查网络或参数。" -ForegroundColor Red
}
Write-Host ""
