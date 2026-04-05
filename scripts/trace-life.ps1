param(
    [string]$ProcessName = "LBA2.EXE",
    [switch]$Launch,
    [string]$GameExe = "",
    [string]$OutputPath = "",
    [string]$FridaRepoRoot = "D:\repos\reverse\frida",
    [int]$TargetObject = 0,
    [int]$TargetOpcode = 0x76,
    [int]$TargetOffset = 46,
    [int]$MaxHits = 1,
    [double]$TimeoutSeconds = 0,
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

$pythonArguments = @(
    $driver,
    "--process", $ProcessName,
    "--output", $OutputPath,
    "--frida-repo-root", (Resolve-Path $FridaRepoRoot).Path,
    "--target-object", $TargetObject,
    "--target-opcode", ("0x{0:X}" -f $TargetOpcode),
    "--target-offset", $TargetOffset,
    "--max-hits", $MaxHits
)

if ($TimeoutSeconds -gt 0) {
    $pythonArguments += @("--timeout-sec", $TimeoutSeconds)
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
