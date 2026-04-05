param(
    [ValidateSet("Server", "Client", "Tail", "Stop")]
    [string]$Mode,
    [string]$ProcessName = "LBA2.EXE",
    [int]$TargetPid = 0,
    [int]$Port = 5005,
    [string]$Password = "",
    [string[]]$Commands = @(),
    [switch]$KeepOpen,
    [string]$LogPath = "",
    [string]$CursorPath = ""
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Find-FirstExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-CdbPath {
    $command = Get-Command cdb -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidate = Find-FirstExistingPath -Candidates @(
        "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe",
        "C:\Program Files (x86)\Windows Kits\10\Debuggers\x86\cdb.exe",
        "C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe",
        "C:\Program Files\Windows Kits\10\Debuggers\x86\cdb.exe"
    )
    if ($candidate) {
        return $candidate
    }

    $appx = Get-AppxPackage Microsoft.WinDbg* -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($appx) {
        $candidate = Find-FirstExistingPath -Candidates @(
            (Join-Path $appx.InstallLocation "amd64\cdb.exe"),
            (Join-Path $appx.InstallLocation "x86\cdb.exe"),
            (Join-Path $appx.InstallLocation "arm64\cdb.exe")
        )
        if ($candidate) {
            return $candidate
        }
    }

    throw "Unable to find cdb.exe on PATH, in the common Windows Kits debugger locations, or inside the installed WinDbg app package."
}

function Get-SessionPaths {
    $repoRoot = Get-RepoRoot
    $workRoot = Join-Path $repoRoot "work\windbg"
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    $resolvedLogPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
        Join-Path $workRoot "cdb.log"
    } else {
        $LogPath
    }
    $resolvedCursorPath = if ([string]::IsNullOrWhiteSpace($CursorPath)) {
        Join-Path $workRoot "cdb.log.pos"
    } else {
        $CursorPath
    }

    return [pscustomobject]@{
        WorkRoot   = $workRoot
        StatePath  = Join-Path $workRoot "cdb-session.json"
        LogPath    = $resolvedLogPath
        CursorPath = $resolvedCursorPath
        LaunchScriptPath = Join-Path $workRoot "start-cdb-server.ps1"
    }
}

function Read-SessionState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    if (-not (Test-Path $StatePath)) {
        return $null
    }

    return Get-Content $StatePath -Raw | ConvertFrom-Json
}

function Remove-SessionState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    if (Test-Path $StatePath) {
        Remove-Item $StatePath -Force
    }
}

function Test-ProcessAlive {
    param(
        [int]$ProcessId
    )

    if ($ProcessId -le 0) {
        return $false
    }

    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Find-CdbProcesses {
    param(
        [string]$DebuggerPath
    )

    return @(Get-Process -Name cdb -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $DebuggerPath })
}

function Resolve-TargetProcess {
    param(
        [string]$RequestedProcessName,
        [int]$RequestedTargetPid
    )

    if ($RequestedTargetPid -gt 0) {
        $process = Get-Process -Id $RequestedTargetPid -ErrorAction SilentlyContinue
        if (-not $process) {
            throw "Target process id $RequestedTargetPid is not running."
        }
        return $process
    }

    $normalizedName = [System.IO.Path]::GetFileNameWithoutExtension($RequestedProcessName)
    $matches = @(Get-Process -Name $normalizedName -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 0) {
        throw "Target process '$RequestedProcessName' is not running. Start LBA2 first, then re-run -Mode Server."
    }
    if ($matches.Count -gt 1) {
        $ids = ($matches | ForEach-Object { $_.Id }) -join ", "
        throw "Multiple '$RequestedProcessName' processes are running ($ids). Re-run with -TargetPid."
    }

    return $matches[0]
}

function New-SessionPassword {
    return ([guid]::NewGuid().ToString("N")).Substring(0, 16)
}

function Get-DebuggerCommands {
    param(
        [string[]]$DebuggerCommands
    )

    return @($DebuggerCommands | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function New-DebuggerCommandFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkRoot,
        [Parameter(Mandatory = $true)]
        [string[]]$Commands
    )

    $normalizedCommands = Get-DebuggerCommands -DebuggerCommands $Commands
    if ($normalizedCommands.Count -eq 0) {
        return $null
    }

    $commandFilePath = Join-Path $WorkRoot ("cdb-client-{0}.cmds" -f ([guid]::NewGuid().ToString("N")))
    $content = ($normalizedCommands -join [Environment]::NewLine) + [Environment]::NewLine
    Set-Content -Path $commandFilePath -Value $content -Encoding ASCII
    return $commandFilePath
}

function Start-DebugServer {
    $paths = Get-SessionPaths
    $repoRoot = Get-RepoRoot
    $cdbPath = Resolve-CdbPath

    $existingState = Read-SessionState -StatePath $paths.StatePath
    if ($existingState) {
        if (Test-ProcessAlive -ProcessId ([int]$existingState.debugger_pid)) {
            throw "A cdb server is already running for this repo (debugger pid $($existingState.debugger_pid)). Use -Mode Stop first."
        }

        Remove-SessionState -StatePath $paths.StatePath
    }

    if (Test-Path $paths.LogPath) {
        Remove-Item $paths.LogPath -Force
    }
    if (Test-Path $paths.CursorPath) {
        Remove-Item $paths.CursorPath -Force
    }

    $targetProcess = Resolve-TargetProcess -RequestedProcessName $ProcessName -RequestedTargetPid $TargetPid
    $sessionPassword = if ([string]::IsNullOrWhiteSpace($Password)) { New-SessionPassword } else { $Password }
    $existingDebuggerPids = @(Find-CdbProcesses -DebuggerPath $cdbPath | ForEach-Object { $_.Id })

    $launchScript = @"
Set-Location '$repoRoot'
& '$cdbPath' -server 'tcp:port=$Port,password=$sessionPassword' -logo '$($paths.LogPath)' -p $($targetProcess.Id) -noio
"@
    Set-Content -Path $paths.LaunchScriptPath -Value $launchScript -Encoding UTF8

    $hostProcess = Start-Process -FilePath pwsh -ArgumentList @("-NoProfile", "-NoExit", "-File", $paths.LaunchScriptPath) -WorkingDirectory $repoRoot -WindowStyle Minimized -PassThru
    Start-Sleep -Seconds 4

    if (-not (Test-ProcessAlive -ProcessId $hostProcess.Id)) {
        throw "The cdb host process exited before the wrapper could confirm it was running."
    }

    $debuggerProcess = Find-CdbProcesses -DebuggerPath $cdbPath | Where-Object { $existingDebuggerPids -notcontains $_.Id } | Select-Object -First 1
    if (-not $debuggerProcess) {
        throw "The cdb host started, but no child cdb.exe process was observed. Check the hosted console window for launch errors."
    }

    $state = [pscustomobject]@{
        debugger_path = $cdbPath
        debugger_pid  = $debuggerProcess.Id
        host_pid      = $hostProcess.Id
        target_pid    = $targetProcess.Id
        process_name  = $targetProcess.ProcessName
        port          = $Port
        password      = $sessionPassword
        log_path      = $paths.LogPath
        cursor_path   = $paths.CursorPath
        launch_script_path = $paths.LaunchScriptPath
        started_utc   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $state | ConvertTo-Json | Set-Content -Path $paths.StatePath -Encoding ASCII

    Write-Host "Started cdb server" -ForegroundColor Cyan
    Write-Host "  host pid:     $($hostProcess.Id)"
    Write-Host "  debugger pid: $($debuggerProcess.Id)"
    Write-Host "  target pid:   $($targetProcess.Id)"
    Write-Host "  remote:       tcp:server=127.0.0.1,port=$Port,password=$sessionPassword"
    Write-Host "  log:          $($paths.LogPath)"
}

function Start-DebugClient {
    $paths = Get-SessionPaths
    $state = Read-SessionState -StatePath $paths.StatePath
    if (-not $state) {
        throw "No cdb session state was found. Start -Mode Server first."
    }
    if (-not (Test-ProcessAlive -ProcessId ([int]$state.debugger_pid))) {
        Remove-SessionState -StatePath $paths.StatePath
        throw "The recorded cdb server (pid $($state.debugger_pid)) is no longer running. Start -Mode Server again."
    }

    $cdbPath = Resolve-CdbPath
    $clientCommands = Get-DebuggerCommands -DebuggerCommands $Commands
    if ($clientCommands.Count -gt 0 -and -not $KeepOpen) {
        $clientCommands += ".remote_exit"
    }

    $argumentList = @(
        "-remote", "tcp:server=127.0.0.1,port=$($state.port),password=$($state.password)",
        "-bonc"
    )

    $commandFilePath = $null
    try {
        $commandFilePath = New-DebuggerCommandFile -WorkRoot $paths.WorkRoot -Commands $clientCommands
        if ($commandFilePath) {
            $argumentList += @("-cf", $commandFilePath)
        }

        & $cdbPath @argumentList
    } finally {
        if ($commandFilePath -and (Test-Path $commandFilePath)) {
            Remove-Item $commandFilePath -Force
        }
    }
}

function Invoke-LogTail {
    $paths = Get-SessionPaths
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "python is required to run the cdb log tail helper."
    }

    $helperPath = Join-Path (Get-RepoRoot) "tools\cdb_tail.py"
    if (-not (Test-Path $helperPath)) {
        throw "Missing cdb tail helper: $helperPath"
    }
    if (-not (Test-Path $paths.LogPath)) {
        throw "No cdb log exists yet at $($paths.LogPath). Start -Mode Server first."
    }

    & $python.Source $helperPath --log $paths.LogPath --cursor $paths.CursorPath
}

function Stop-DebugServer {
    $paths = Get-SessionPaths
    $state = Read-SessionState -StatePath $paths.StatePath
    if (-not $state) {
        Write-Host "No cdb session state to stop." -ForegroundColor Yellow
        return
    }

    if (Test-ProcessAlive -ProcessId ([int]$state.debugger_pid)) {
        $cdbPath = Resolve-CdbPath
        $argumentList = @(
            "-remote", "tcp:server=127.0.0.1,port=$($state.port),password=$($state.password)",
            "-bonc"
        )

        $commandFilePath = $null
        try {
            $commandFilePath = New-DebuggerCommandFile -WorkRoot $paths.WorkRoot -Commands @(
                ".detach",
                "q"
            )
            if ($commandFilePath) {
                $argumentList += @("-cf", $commandFilePath)
            }

            & $cdbPath @argumentList | Out-Null
        } catch {
            Write-Warning "Best-effort cdb shutdown command failed; falling back to Stop-Process."
        } finally {
            if ($commandFilePath -and (Test-Path $commandFilePath)) {
                Remove-Item $commandFilePath -Force
            }
        }

        Start-Sleep -Milliseconds 750
        if (Test-ProcessAlive -ProcessId ([int]$state.debugger_pid)) {
            Stop-Process -Id ([int]$state.debugger_pid) -Force
        }
    }

    if ($state.host_pid -and (Test-ProcessAlive -ProcessId ([int]$state.host_pid))) {
        Stop-Process -Id ([int]$state.host_pid) -Force
    }

    Remove-SessionState -StatePath $paths.StatePath
    if ($state.launch_script_path -and (Test-Path $state.launch_script_path)) {
        Remove-Item $state.launch_script_path -Force
    }
    Write-Host "Stopped cdb server state for this repo." -ForegroundColor Cyan
}

switch ($Mode) {
    "Server" { Start-DebugServer }
    "Client" { Start-DebugClient }
    "Tail" { Invoke-LogTail }
    "Stop" { Stop-DebugServer }
}
