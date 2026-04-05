param(
    [switch]$Fast
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Stop-StaleViewerProcesses {
    $stale = Get-Process lba2 -ErrorAction SilentlyContinue
    if ($stale) {
        Write-Host "Stopping stale lba2.exe process(es)." -ForegroundColor Yellow
        $stale | Stop-Process -Force
        Start-Sleep -Milliseconds 250
    }
}

function Invoke-ZigCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host ("=== {0} ===" -f $Label) -ForegroundColor Cyan

    Push-Location $WorkingDirectory
    try {
        $output = (& zig @Arguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $trimmed = $output.TrimEnd()
    if ($trimmed.Length -gt 0) {
        Write-Host $trimmed
    }

    if ($exitCode -ne 0) {
        throw ("zig {0} failed with exit code {1}." -f ($Arguments -join " "), $exitCode)
    }

    return $output
}

function Invoke-ExecutableCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host ("=== {0} ===" -f $Label) -ForegroundColor Cyan

    Push-Location $WorkingDirectory
    try {
        $output = (& $FilePath @Arguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $trimmed = $output.TrimEnd()
    if ($trimmed.Length -gt 0) {
        Write-Host $trimmed
    }

    return [pscustomobject]@{
        Output   = $output
        ExitCode = $exitCode
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        $Actual,
        [Parameter(Mandatory = $true)]
        $Expected
    )

    if ($Actual -ne $Expected) {
        throw ("{0}: expected {1}, got {2}." -f $Label, $Expected, $Actual)
    }
}

function Test-InspectRoomSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PortRoot,
        [Parameter(Mandatory = $true)]
        [string]$ToolPath,
        [Parameter(Mandatory = $true)]
        [int]$Scene,
        [Parameter(Mandatory = $true)]
        [int]$Background,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedFragments,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedGrmEntry
    )

    $result = Invoke-ExecutableCommand -WorkingDirectory $PortRoot -FilePath $ToolPath -Label ("lba2-tool inspect-room {0} {1} --json" -f $Scene, $Background) -Arguments @(
        "inspect-room",
        "$Scene",
        "$Background",
        "--json"
    )
    if ($result.ExitCode -ne 0) {
        throw ("inspect-room {0}/{1} failed with exit code {2}." -f $Scene, $Background, $result.ExitCode)
    }

    $payload = $result.Output | ConvertFrom-Json

    Assert-Equal -Label "inspect-room command" -Actual $payload.command -Expected "inspect-room"
    Assert-Equal -Label "scene entry index" -Actual $payload.scene.entry_index -Expected $Scene
    Assert-Equal -Label "background entry index" -Actual $payload.background.entry_index -Expected $Background
    Assert-Equal -Label "scene kind" -Actual $payload.scene.scene_kind -Expected "interior"
    Assert-Equal -Label "fragment count for $Scene/$Background" -Actual $payload.background.fragments.fragment_count -Expected $ExpectedFragments
    Assert-Equal -Label "GRM entry for $Scene/$Background" -Actual $payload.background.linkage.grm_entry_index -Expected $ExpectedGrmEntry

    return [pscustomobject]@{
        Pair          = "{0}/{1}" -f $Scene, $Background
        Fragments     = [int]$payload.background.fragments.fragment_count
        BrickPreviews = [int]$payload.background.bricks.preview_count
        GrmEntry      = [int]$payload.background.linkage.grm_entry_index
    }
}

function Test-InspectRoomFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PortRoot,
        [Parameter(Mandatory = $true)]
        [string]$ToolPath,
        [Parameter(Mandatory = $true)]
        [int]$Scene,
        [Parameter(Mandatory = $true)]
        [int]$Background,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedError
    )

    $result = Invoke-ExecutableCommand -WorkingDirectory $PortRoot -FilePath $ToolPath -Label ("lba2-tool inspect-room {0} {1} --json (expected failure)" -f $Scene, $Background) -Arguments @(
        "inspect-room",
        "$Scene",
        "$Background",
        "--json"
    )

    if ($result.ExitCode -eq 0) {
        throw ("inspect-room {0}/{1} unexpectedly succeeded." -f $Scene, $Background)
    }
    if ($result.Output -notmatch [regex]::Escape($ExpectedError)) {
        throw ("inspect-room {0}/{1} failed, but did not mention {2}. Output:`n{3}" -f $Scene, $Background, $ExpectedError, $result.Output.TrimEnd())
    }

    return [pscustomobject]@{
        Pair   = "{0}/{1}" -f $Scene, $Background
        Status = "rejected"
        Error  = $ExpectedError
    }
}

function Test-ViewerLaunch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PortRoot,
        [Parameter(Mandatory = $true)]
        [string]$ViewerPath,
        [Parameter(Mandatory = $true)]
        [int]$Scene,
        [Parameter(Mandatory = $true)]
        [int]$Background,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedFragments,
        [int]$ExpectedBrickPreviews = -1
    )

    Write-Host ""
    Write-Host ("=== lba2 --scene-entry {0} --background-entry {1} ===" -f $Scene, $Background) -ForegroundColor Cyan

    Stop-StaleViewerProcesses

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $proc = $null

    try {
        $proc = Start-Process -FilePath $ViewerPath -WorkingDirectory $PortRoot -ArgumentList @(
            "--scene-entry",
            "$Scene",
            "--background-entry",
            "$Background"
        ) -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

        $confirmed = $false
        $deadline = (Get-Date).AddSeconds(120)

        while ((Get-Date) -lt $deadline) {
            $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
            $startupSeen = $stderr -match "event=startup"
            $roomSnapshotSeen = $stderr -match "event=room_snapshot"
            $pairSeen = $stderr -match ("scene_entry_index={0} background_entry_index={1}" -f $Scene, $Background)
            $renderSnapshotSeen = $stderr -match "render_snapshot=objects:"
            $fragmentSummarySeen = $stderr -match ("fragments={0}\s" -f $ExpectedFragments)
            $brickPreviewSummarySeen = ($ExpectedBrickPreviews -lt 0) -or ($stderr -match ("brick_previews={0}" -f $ExpectedBrickPreviews))
            $viewerProcess = Get-Process lba2 -ErrorAction SilentlyContinue

            if ($viewerProcess -and $startupSeen -and $roomSnapshotSeen -and $pairSeen -and $renderSnapshotSeen -and $fragmentSummarySeen -and $brickPreviewSummarySeen) {
                $confirmed = $true
                break
            }

            if ($proc.HasExited) {
                break
            }

            Start-Sleep -Milliseconds 500
        }

        $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
        $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { "" }

        if (-not $confirmed) {
            throw ("viewer launch {0}/{1} did not reach confirmed startup.`nstderr:`n{2}`nstdout:`n{3}" -f $Scene, $Background, $stderr.TrimEnd(), $stdout.TrimEnd())
        }

        Write-Host $stderr.TrimEnd()

        return [pscustomobject]@{
            Pair          = "{0}/{1}" -f $Scene, $Background
            Startup       = "confirmed"
            Fragments     = $ExpectedFragments
            BrickPreviews = if ($ExpectedBrickPreviews -lt 0) { "n/a" } else { $ExpectedBrickPreviews }
        }
    }
    finally {
        Stop-StaleViewerProcesses

        if ($proc -and -not $proc.HasExited) {
            $proc.WaitForExit(15000) | Out-Null
        }
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }

        Remove-Item $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }
}

$repoRoot = Get-RepoRoot
$portRoot = Join-Path $repoRoot "port"
$devShell = Join-Path $repoRoot "scripts\dev-shell.ps1"

Write-Host "Configuring native PowerShell dev shell." -ForegroundColor Cyan
& $devShell -Quiet

$inspectSuccessResults = [System.Collections.Generic.List[object]]::new()
$inspectFailureResults = [System.Collections.Generic.List[object]]::new()
$launchResults = [System.Collections.Generic.List[object]]::new()

$testStep = if ($Fast) { "test-fast" } else { "test" }
Invoke-ZigCommand -WorkingDirectory $portRoot -Label ("zig build {0}" -f $testStep) -Arguments @("build", $testStep) | Out-Null
Invoke-ZigCommand -WorkingDirectory $portRoot -Label "zig build stage-viewer" -Arguments @("build", "stage-viewer") | Out-Null

$toolPath = Join-Path $portRoot "zig-out\bin\lba2-tool.exe"
$viewerPath = Join-Path $portRoot "zig-out\bin\lba2.exe"
if (-not (Test-Path $toolPath)) {
    throw ("Missing staged tool binary: {0}" -f $toolPath)
}
if (-not (Test-Path $viewerPath)) {
    throw ("Missing staged viewer binary: {0}" -f $viewerPath)
}

$inspectSuccessResults.Add((Test-InspectRoomSuccess -PortRoot $portRoot -ToolPath $toolPath -Scene 19 -Background 19 -ExpectedFragments 0 -ExpectedGrmEntry 151))
$inspectFailureResults.Add((Test-InspectRoomFailure -PortRoot $portRoot -ToolPath $toolPath -Scene 2 -Background 2 -ExpectedError "ViewerUnsupportedSceneLife"))
$inspectFailureResults.Add((Test-InspectRoomFailure -PortRoot $portRoot -ToolPath $toolPath -Scene 44 -Background 2 -ExpectedError "ViewerUnsupportedSceneLife"))
$inspectFailureResults.Add((Test-InspectRoomFailure -PortRoot $portRoot -ToolPath $toolPath -Scene 11 -Background 10 -ExpectedError "ViewerUnsupportedSceneLife"))

$launchResults.Add((Test-ViewerLaunch -PortRoot $portRoot -ViewerPath $viewerPath -Scene 19 -Background 19 -ExpectedFragments 0))

Write-Host ""
Write-Host "Viewer verification summary" -ForegroundColor Green
$inspectSuccessResults | Format-Table Pair, Fragments, BrickPreviews, GrmEntry -AutoSize
$inspectFailureResults | Format-Table Pair, Status, Error -AutoSize
$launchResults | Format-Table Pair, Startup, Fragments, BrickPreviews -AutoSize

Write-Host ""
Write-Host "status=ok" -ForegroundColor Green
