param(
    [ValidateSet("x64", "x86")]
    [string]$Arch = "x64",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-VcVarsCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Arch
    )

    $fileName = if ($Arch -eq "x64") { "vcvars64.bat" } else { "vcvars32.bat" }
    $candidates = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\$fileName",
        "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\$fileName",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\$fileName"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Import-BatchEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchFile
    )

    $output = & cmd.exe /d /c "call `"$BatchFile`" >nul && set"
    foreach ($line in $output) {
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) {
            continue
        }

        $name = $line.Substring(0, $idx)
        $value = $line.Substring($idx + 1)
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function Get-ToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    return $null
}

$repoRoot = Get-RepoRoot
$vcvars = Get-VcVarsCandidate -Arch $Arch

if (-not $vcvars) {
    throw "Could not find a Visual Studio vcvars script for arch '$Arch'."
}

Import-BatchEnvironment -BatchFile $vcvars

[Environment]::SetEnvironmentVariable("LBA2_REPO_ROOT", $repoRoot, "Process")
[Environment]::SetEnvironmentVariable("LBA2_ORIGINAL_CD_ROOT", (Join-Path $repoRoot "work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2"), "Process")
[Environment]::SetEnvironmentVariable("LBA2_SOURCE_ROOT", (Join-Path $repoRoot "reference\lba2-classic"), "Process")
[Environment]::SetEnvironmentVariable("LBA2_MBN_TOOLS_ROOT", (Join-Path $repoRoot "reference\littlebigreversing\mbn_tools"), "Process")

if (-not $Quiet) {
    Write-Host "Developer shell configured." -ForegroundColor Green
    Write-Host "  Arch: $Arch"
    Write-Host "  vcvars: $vcvars"
    Write-Host "  Repo: $repoRoot"
    Write-Host ""

    foreach ($tool in @("cl", "cmake", "ninja", "msbuild", "python", "java")) {
        $toolPath = Get-ToolPath -Name $tool
        if ($toolPath) {
            Write-Host ("  {0,-8} {1}" -f $tool, $toolPath)
        } else {
            Write-Host ("  {0,-8} <not found in PATH>" -f $tool) -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "Environment variables set:" -ForegroundColor Cyan
    Write-Host "  LBA2_REPO_ROOT"
    Write-Host "  LBA2_ORIGINAL_CD_ROOT"
    Write-Host "  LBA2_SOURCE_ROOT"
    Write-Host "  LBA2_MBN_TOOLS_ROOT"
    Write-Host ""
    Write-Host "Run this script from PowerShell before building modern tooling."
}
