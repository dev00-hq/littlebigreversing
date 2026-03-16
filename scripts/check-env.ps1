param()

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

function Add-CheckResult {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [string]$Details = ""
    )

    $Results.Add([pscustomobject]@{
        Category = $Category
        Name     = $Name
        Status   = $Status
        Details  = $Details
    })
}

$repoRoot = Get-RepoRoot
$results = [System.Collections.Generic.List[object]]::new()

$paths = [ordered]@{
    "Repo root"            = $repoRoot
    "Historic source tree" = (Join-Path $repoRoot "reference\lba2-classic")
    "MBN tools"            = (Join-Path $repoRoot "reference\littlebigreversing\mbn_tools")
    "Extracted CD data"    = (Join-Path $repoRoot "work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2")
    "Porting report"       = (Join-Path $repoRoot "docs\PORTING_REPORT.md")
    "Ghidra"               = "D:\repos\reverse\ghidra"
    "x64dbg"               = "D:\repos\reverse\x64dbg"
    "Detect It Easy"       = "D:\repos\reverse\Detect-It-Easy"
    "PE-bear"              = "D:\repos\reverse\PE-bear_0.7.1_qt6.8_x64_win_vs22\PE-bear.exe"
}

foreach ($entry in $paths.GetEnumerator()) {
    if (Test-Path $entry.Value) {
        Add-CheckResult -Results $results -Category "Paths" -Name $entry.Key -Status "OK" -Details $entry.Value
    } else {
        Add-CheckResult -Results $results -Category "Paths" -Name $entry.Key -Status "Missing" -Details $entry.Value
    }
}

$vsVcVars = Find-FirstExistingPath -Candidates @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
$cmake = Find-FirstExistingPath -Candidates @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
)
$ninja = Find-FirstExistingPath -Candidates @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
)
$msbuild = Find-FirstExistingPath -Candidates @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
)
$cl = Find-FirstExistingPath -Candidates @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433\bin\Hostx64\x64\cl.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64\cl.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64\cl.exe"
)
$ml = Find-FirstExistingPath -Candidates @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433\bin\Hostx64\x86\ml.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x86\ml.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x86\ml.exe"
)

foreach ($tool in @(
    @{ Name = "Visual Studio vcvars"; Path = $vsVcVars },
    @{ Name = "CMake"; Path = $cmake },
    @{ Name = "Ninja"; Path = $ninja },
    @{ Name = "MSBuild"; Path = $msbuild },
    @{ Name = "MSVC cl"; Path = $cl },
    @{ Name = "MASM ml"; Path = $ml }
)) {
    if ($tool.Path) {
        Add-CheckResult -Results $results -Category "Modern build" -Name $tool.Name -Status "OK" -Details $tool.Path
    } else {
        Add-CheckResult -Results $results -Category "Modern build" -Name $tool.Name -Status "Missing" -Details ""
    }
}

$python = Get-Command python -ErrorAction SilentlyContinue
$java = Get-Command java -ErrorAction SilentlyContinue
$git = Get-Command git -ErrorAction SilentlyContinue
$sevenZip = Get-Command 7z -ErrorAction SilentlyContinue

foreach ($cmd in @(
    @{ Name = "Python"; Cmd = $python },
    @{ Name = "Java"; Cmd = $java },
    @{ Name = "Git"; Cmd = $git },
    @{ Name = "7-Zip"; Cmd = $sevenZip }
)) {
    if ($cmd.Cmd) {
        Add-CheckResult -Results $results -Category "General tools" -Name $cmd.Name -Status "OK" -Details $cmd.Cmd.Source
    } else {
        Add-CheckResult -Results $results -Category "General tools" -Name $cmd.Name -Status "Missing" -Details ""
    }
}

$dosbox = Find-FirstExistingPath -Candidates @(
    (Join-Path $repoRoot "reference\lba2-classic\Speedrun\Windows\DOSBOX\DOSBox.exe"),
    (Join-Path $repoRoot "work\_innoextract_full\Speedrun\Windows\DOSBOX\DOSBox.exe")
)
$dosboxX = Find-FirstExistingPath -Candidates @(
    "C:\Program Files\DOSBox-X\dosbox-x.exe",
    "C:\Program Files (x86)\DOSBox-X\dosbox-x.exe",
    "D:\repos\reverse\DOSBox-X\dosbox-x.exe"
)
$openWatcom = Find-FirstExistingPath -Candidates @(
    "C:\WATCOM\BINNT64\wmake.exe",
    "C:\WATCOM\BINNT\wmake.exe",
    "C:\OpenWatcom\BINNT64\wmake.exe",
    "C:\OpenWatcom\BINNT\wmake.exe"
)
$sdl2Header = Find-FirstExistingPath -Candidates @(
    (Join-Path $repoRoot "vcpkg_installed\x64-windows\include\SDL2\SDL.h"),
    "C:\SDL2\include\SDL.h",
    "C:\SDL2\include\SDL2\SDL.h",
    "C:\vcpkg\installed\x64-windows\include\SDL2\SDL.h",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg\installed\x64-windows\include\SDL2\SDL.h"
)
$sdl2Lib = Find-FirstExistingPath -Candidates @(
    (Join-Path $repoRoot "vcpkg_installed\x64-windows\lib\SDL2.lib"),
    "C:\SDL2\lib\x64\SDL2.lib",
    "C:\vcpkg\installed\x64-windows\lib\SDL2.lib",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg\installed\x64-windows\lib\SDL2.lib"
)

foreach ($tool in @(
    @{ Name = "DOSBox runtime"; Path = $dosbox; Category = "Reference build" },
    @{ Name = "DOSBox-X"; Path = $dosboxX; Category = "Reference build" },
    @{ Name = "OpenWatcom"; Path = $openWatcom; Category = "Reference build" },
    @{ Name = "SDL2 headers"; Path = $sdl2Header; Category = "Modern port" },
    @{ Name = "SDL2 library"; Path = $sdl2Lib; Category = "Modern port" }
)) {
    if ($tool.Path) {
        Add-CheckResult -Results $results -Category $tool.Category -Name $tool.Name -Status "OK" -Details $tool.Path
    } else {
        Add-CheckResult -Results $results -Category $tool.Category -Name $tool.Name -Status "Missing" -Details ""
    }
}

Write-Host ""
Write-Host "LBA2 environment check" -ForegroundColor Cyan
Write-Host ("Repo: {0}" -f $repoRoot)
Write-Host ""

$results |
    Sort-Object Category, Name |
    Format-Table -AutoSize

$missing = $results | Where-Object { $_.Status -eq "Missing" }

Write-Host ""
if ($missing.Count -eq 0) {
    Write-Host "No missing items detected in this check." -ForegroundColor Green
} else {
    Write-Host "Missing items detected:" -ForegroundColor Yellow
    foreach ($item in $missing) {
        Write-Host ("  - [{0}] {1}" -f $item.Category, $item.Name)
    }
}

Write-Host ""
Write-Host "Recommended next installs, in order:" -ForegroundColor Cyan
Write-Host "  1. DOSBox-X for DOS-side runtime investigation"
Write-Host "  2. OpenWatcom for historic-build experiments"
Write-Host "  3. SDL2 development package for the modern port"
Write-Host ""
Write-Host "Use .\scripts\dev-shell.ps1 before running modern CMake/MSVC commands."
