param()

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

function Test-InspectRoom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PortRoot,
        [Parameter(Mandatory = $true)]
        [int]$Scene,
        [Parameter(Mandatory = $true)]
        [int]$Background,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedFragments,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedBrickPreviews,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedGrmEntry
    )

    $json = Invoke-ZigCommand -WorkingDirectory $PortRoot -Label ("zig build tool -- inspect-room {0} {1} --json" -f $Scene, $Background) -Arguments @(
        "build",
        "tool",
        "--",
        "inspect-room",
        "$Scene",
        "$Background",
        "--json"
    )

    $payload = $json | ConvertFrom-Json

    Assert-Equal -Label "inspect-room command" -Actual $payload.command -Expected "inspect-room"
    Assert-Equal -Label "scene entry index" -Actual $payload.scene.entry_index -Expected $Scene
    Assert-Equal -Label "background entry index" -Actual $payload.background.entry_index -Expected $Background
    Assert-Equal -Label "scene kind" -Actual $payload.scene.scene_kind -Expected "interior"
    Assert-Equal -Label "fragment count for $Scene/$Background" -Actual $payload.background.fragments.fragment_count -Expected $ExpectedFragments
    Assert-Equal -Label "brick preview count for $Scene/$Background" -Actual $payload.background.bricks.preview_count -Expected $ExpectedBrickPreviews
    Assert-Equal -Label "GRM entry for $Scene/$Background" -Actual $payload.background.linkage.grm_entry_index -Expected $ExpectedGrmEntry

    return [pscustomobject]@{
        Pair          = "{0}/{1}" -f $Scene, $Background
        Fragments     = [int]$payload.background.fragments.fragment_count
        BrickPreviews = [int]$payload.background.bricks.preview_count
        GrmEntry      = [int]$payload.background.linkage.grm_entry_index
    }
}

function Test-ViewerLaunch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PortRoot,
        [Parameter(Mandatory = $true)]
        [int]$Scene,
        [Parameter(Mandatory = $true)]
        [int]$Background,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedFragments,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedBrickPreviews
    )

    Write-Host ""
    Write-Host ("=== zig build run -- --scene-entry {0} --background-entry {1} ===" -f $Scene, $Background) -ForegroundColor Cyan

    Stop-StaleViewerProcesses

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $proc = $null

    try {
        $proc = Start-Process -FilePath "zig" -WorkingDirectory $PortRoot -ArgumentList @(
            "build",
            "run",
            "--",
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
            $brickPreviewSummarySeen = $stderr -match ("brick_previews={0}" -f $ExpectedBrickPreviews)
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
            BrickPreviews = $ExpectedBrickPreviews
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

$inspectResults = [System.Collections.Generic.List[object]]::new()
$launchResults = [System.Collections.Generic.List[object]]::new()

Invoke-ZigCommand -WorkingDirectory $portRoot -Label "zig build test" -Arguments @("build", "test") | Out-Null

$inspectResults.Add((Test-InspectRoom -PortRoot $portRoot -Scene 11 -Background 10 -ExpectedFragments 1 -ExpectedBrickPreviews 261 -ExpectedGrmEntry 149))
$inspectResults.Add((Test-InspectRoom -PortRoot $portRoot -Scene 2 -Background 2 -ExpectedFragments 0 -ExpectedBrickPreviews 188 -ExpectedGrmEntry 149))

$launchResults.Add((Test-ViewerLaunch -PortRoot $portRoot -Scene 11 -Background 10 -ExpectedFragments 1 -ExpectedBrickPreviews 261))
$launchResults.Add((Test-ViewerLaunch -PortRoot $portRoot -Scene 2 -Background 2 -ExpectedFragments 0 -ExpectedBrickPreviews 188))

Write-Host ""
Write-Host "Viewer verification summary" -ForegroundColor Green
$inspectResults | Format-Table Pair, Fragments, BrickPreviews, GrmEntry -AutoSize
$launchResults | Format-Table Pair, Startup, Fragments, BrickPreviews -AutoSize

Write-Host ""
Write-Host "status=ok" -ForegroundColor Green
