param(
    [ValidateSet("Basic", "TavernTrace", "Scene11Pair")]
    [string]$Mode = "Basic",
    [string]$ProcessName = "LBA2.EXE",
    [switch]$Launch,
    [string]$GameExe = "",
    [string]$OutputPath = "",
    [string]$ScreenshotDir = "",
    [string]$FridaRepoRoot = "D:\repos\reverse\frida",
    [int]$TargetObject = 0,
    [int]$TargetOpcode = 0x76,
    [int]$TargetOffset = 46,
    [int]$MaxHits = 1,
    [Nullable[double]]$TimeoutSeconds = $null,
    [switch]$KeepAlive,
    [switch]$LogAll
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$toolRoot = Join-Path $repoRoot "tools\life_trace"
$driver = Join-Path $toolRoot "trace_life.py"
$defaultGameExe = Join-Path $repoRoot "work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\LBA2.EXE"

if (-not (Test-Path $driver)) {
    throw "Missing trace driver: $driver"
}

$python = Get-Command python -ErrorAction Stop
if (-not (Test-Path $FridaRepoRoot)) {
    throw "Frida repo root not found: $FridaRepoRoot"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDir = Join-Path $repoRoot "work\life_trace"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $outputDir "life-trace-$timestamp.jsonl"
}

$resolvedMode = switch ($Mode) {
    "TavernTrace" { "tavern-trace" }
    "Scene11Pair" { "scene11-pair" }
    default { "basic" }
}
$resolvedTimeoutSeconds = $TimeoutSeconds

if ($Mode -in @("TavernTrace", "Scene11Pair")) {
    $conflictingFlags = @()
    foreach ($parameterName in @("TargetObject", "TargetOpcode", "TargetOffset")) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $conflictingFlags += "-$parameterName"
        }
    }

    if ($conflictingFlags.Count -gt 0) {
        throw "The following flags conflict with -Mode ${Mode}: $($conflictingFlags -join ', ')"
    }

    if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
        $ScreenshotDir = Join-Path $repoRoot "work\life_trace\shots"
    }

    New-Item -ItemType Directory -Path $ScreenshotDir -Force | Out-Null

    if (-not $PSBoundParameters.ContainsKey("TimeoutSeconds")) {
        $resolvedTimeoutSeconds = 60
    }
} elseif (-not [string]::IsNullOrWhiteSpace($ScreenshotDir)) {
    throw "-ScreenshotDir is only supported with -Mode TavernTrace or -Mode Scene11Pair"
}

$pythonArguments = @(
    $driver,
    "--mode", $resolvedMode,
    "--process", $ProcessName,
    "--output", $OutputPath,
    "--frida-repo-root", (Resolve-Path $FridaRepoRoot).Path,
    "--max-hits", $MaxHits
)

if ($Mode -in @("TavernTrace", "Scene11Pair")) {
    $pythonArguments += @("--screenshot-dir", (Resolve-Path $ScreenshotDir).Path)
} else {
    $pythonArguments += @(
        "--target-object", $TargetObject,
        "--target-opcode", ("0x{0:X}" -f $TargetOpcode),
        "--target-offset", $TargetOffset
    )
}

if ($resolvedTimeoutSeconds -ne $null) {
    $pythonArguments += @("--timeout-sec", [string]$resolvedTimeoutSeconds)
}

if ($KeepAlive) {
    $pythonArguments += "--keep-alive"
}

if ($LogAll) {
    $pythonArguments += "--log-all"
}

if ($Launch) {
    if ([string]::IsNullOrWhiteSpace($GameExe)) {
        $GameExe = $defaultGameExe
    }

    if (-not (Test-Path $GameExe)) {
        throw "Game executable not found: $GameExe"
    }

    $pythonArguments += @("--launch", (Resolve-Path $GameExe).Path)
}

Write-Host "Tracing life interpreter events to $OutputPath" -ForegroundColor Cyan
& $python.Source @pythonArguments
