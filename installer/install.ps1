<#
.SYNOPSIS
  Windows 安装器 —— 一条命令完成本地安装并可直接使用 `cx`。

.DESCRIPTION
  改自官方 codex/scripts/install/install.ps1，做了三处裁剪与改造（与 install.sh 对齐）：
    1. 去掉全部 GitHub 下载 / 校验 / 版本解析逻辑（Resolve-Version / Invoke-WebRequest /
       Test-ArchiveDigest / 各 *ReleaseAsset* 函数全部移除）：二进制随安装器本地分发。
    2. 去掉 standalone releases/current junction 多版本布局（Ensure-Junction / 安装锁 /
       旧布局迁移全部移除）：直接把本地 cx.exe 装成 $BinDir\cx.exe（单文件）。
    3. 命令名 codex → cx；装完二进制后调用 US-008 的 installer\write-default-config.ps1
       幂等写入内置渠道 config。

  保留官方成熟的 PATH 注入逻辑（写用户环境变量 Path，对 PowerShell 和 CMD 新会话都生效），
  保证「安装完成后 cx 可在新 PowerShell/CMD 会话直接调用」。

  ── 二进制从哪来 ─────────────────────────────────────────────────
    优先级：-Binary PATH > $env:CX_BINARY > 脚本同目录自动探测。
    自动探测按当前 Windows 架构找脚本同目录下的：
      arm64 → cx-aarch64-pc-windows-msvc.exe，x64 → cx-x86_64-pc-windows-msvc.exe，
    都没有则回退到通用文件名 cx.exe。
    这些文件由 GitHub Actions（build.yml）编译产出（US-009），打包时随安装器分发。

.PARAMETER Binary
  指定本地 cx.exe 二进制路径（覆盖自动探测）。

.PARAMETER Config
  指定随安装器分发的成品 config.toml 路径（默认脚本同目录 config.toml）。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File installer\install.ps1

.NOTES
  环境变量：
    CX_INSTALL_DIR  安装目录（默认 $env:LOCALAPPDATA\Programs\cx\bin）。
    CX_BINARY       本地 cx.exe 二进制路径（等价 -Binary）。
    CX_CONFIG       成品 config.toml 路径（等价 -Config）。
    CODEX_HOME      配置目录（默认 $HOME\.codex，与 codex 本体一致）。
#>
[CmdletBinding()]
param(
    [string]$Binary = $env:CX_BINARY,
    [string]$Config = $env:CX_CONFIG
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$CommandName = "cx"
$ExeName = "$CommandName.exe"

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Write-WarningStep {
    param([string]$Message)
    Write-Warning $Message
}

# PATH 去重判定：分号切分，逐段忽略大小写与尾随反斜杠比对。
function Path-Contains {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $needle = $Entry.TrimEnd("\")
    foreach ($segment in $PathValue.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        if ($segment.TrimEnd("\") -ieq $needle) {
            return $true
        }
    }

    return $false
}

# 定位本地二进制：-Binary/$env:CX_BINARY 优先，否则按当前 Windows 架构在脚本同目录探测，
# 依次找 cx-<target>.exe，回退到通用文件名 cx.exe。
function Resolve-Binary {
    param(
        [string]$ScriptDir,
        [string]$Target,
        [string]$Override
    )

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) {
            throw "指定的二进制不存在: $Override"
        }
        return (Resolve-Path -LiteralPath $Override).Path
    }

    $candidates = @(
        (Join-Path $ScriptDir "$CommandName-$Target.exe"),
        (Join-Path $ScriptDir $ExeName)
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "找不到本地 $CommandName 二进制（在 $ScriptDir 下查找 $CommandName-$Target.exe 或 $ExeName）。`n请用 -Binary PATH 指定，或把 CI 产出的二进制放到安装器同目录。"
}

if ($env:OS -ne "Windows_NT") {
    Write-Error "install.ps1 仅支持 Windows。macOS/Linux 请用 install.sh。"
    exit 1
}

if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Error "$CommandName 需要 64 位 Windows。"
    exit 1
}

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
switch ($architecture) {
    "Arm64" {
        $target = "aarch64-pc-windows-msvc"
        $platformLabel = "Windows (ARM64)"
    }
    "X64" {
        $target = "x86_64-pc-windows-msvc"
        $platformLabel = "Windows (x64)"
    }
    default {
        Write-Error "不支持的架构: $architecture"
        exit 1
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 安装目录：CX_INSTALL_DIR 优先，否则 $LOCALAPPDATA\Programs\cx\bin。
if ([string]::IsNullOrWhiteSpace($env:CX_INSTALL_DIR)) {
    $binDir = Join-Path $env:LOCALAPPDATA "Programs\$CommandName\bin"
} else {
    $binDir = $env:CX_INSTALL_DIR
}
$binPath = Join-Path $binDir $ExeName

$binarySrc = Resolve-Binary -ScriptDir $scriptDir -Target $target -Override $Binary

Write-Step "安装 $CommandName CLI"
Write-Step "检测到平台: $platformLabel"
Write-Step "使用本地二进制: $binarySrc"

# ── 放置二进制 ────────────────────────────────────────────────────
Write-Step "安装二进制到 $binPath"
if (-not (Test-Path -LiteralPath $binDir -PathType Container)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}
# 先拷到临时文件再原子替换，避免二进制正在运行时的半写状态。
$tmpBin = Join-Path $binDir (".{0}.{1}.tmp" -f $ExeName, $PID)
Copy-Item -LiteralPath $binarySrc -Destination $tmpBin -Force
Move-Item -LiteralPath $tmpBin -Destination $binPath -Force

# ── 写内置渠道配置（委托 US-008 幂等脚本）─────────────────────────
$writer = Join-Path $scriptDir "write-default-config.ps1"
$configSrc = $Config
if ([string]::IsNullOrWhiteSpace($configSrc)) {
    $configSrc = Join-Path $scriptDir "config.toml"
}

if (-not (Test-Path -LiteralPath $writer -PathType Leaf)) {
    Write-WarningStep "未找到 $writer，跳过内置渠道配置写入。首次运行 $CommandName 前请手动配置 config.toml。"
} elseif (-not (Test-Path -LiteralPath $configSrc -PathType Leaf)) {
    Write-WarningStep "未找到成品配置 $configSrc，跳过内置渠道配置写入。首次运行 $CommandName 前请手动配置。"
} else {
    Write-Step "写入内置渠道配置（幂等）"
    & $writer -SourceConfig $configSrc
}

# ── 加入 PATH（写用户环境变量，PowerShell + CMD 新会话都生效）──────
# 用户级 Path 是 PowerShell 与 CMD 共享的持久环境变量，写一次两边新会话都能用。
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not (Path-Contains -PathValue $userPath -Entry $binDir)) {
    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $newUserPath = $binDir
    } else {
        $newUserPath = "$binDir;$userPath"
    }
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Write-Step "已把 PATH 写入用户环境变量（新 PowerShell/CMD 会话生效）。"
    $pathAdded = $true
} else {
    Write-Step "$binDir 已在用户 PATH 中。"
    $pathAdded = $false
}

# 同步当前会话的 $env:Path，便于安装完立即在本会话用 cx。
if (-not (Path-Contains -PathValue $env:Path -Entry $binDir)) {
    if ([string]::IsNullOrWhiteSpace($env:Path)) {
        $env:Path = $binDir
    } else {
        $env:Path = "$binDir;$env:Path"
    }
}

# ── 验证 cx 可用 ─────────────────────────────────────────────────
& $binPath --version *> $null
if ($LASTEXITCODE -ne 0) {
    throw "已安装的 $CommandName 命令验证失败: $binPath --version"
}

Write-Step "当前会话: $CommandName"
Write-Step "新 PowerShell/CMD 会话: 打开新窗口后直接运行: $CommandName"
if ($pathAdded) {
    Write-Step "PATH 已写入用户环境变量，重开终端即可直接用 $CommandName。"
}

Write-Host "$CommandName CLI 安装成功。"
