param(
    [string]$GameDir = "$PSScriptRoot\..\..\..\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2",
    [string]$DllPath = "$PSScriptRoot\..\..\..\build\runtime_shims\lba2_winmm_proxy\winmm.dll",
    [switch]$Build
)

$ErrorActionPreference = "Stop"

if ($Build) {
    & "$PSScriptRoot\build.ps1" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$resolvedGameDir = Resolve-Path -LiteralPath $GameDir
$resolvedDll = Resolve-Path -LiteralPath $DllPath
$target = Join-Path $resolvedGameDir "winmm.dll"

if (Test-Path -LiteralPath $target) {
    $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
    $newHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedDll).Hash
    if ($existingHash -ne $newHash) {
        $backup = Join-Path $resolvedGameDir ("winmm.dll.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        Move-Item -LiteralPath $target -Destination $backup
        Write-Output "Backed up existing winmm.dll to $backup"
    }
}

$realTarget = Join-Path $resolvedGameDir "winmm_real.dll"
$systemWinmm = Join-Path $env:WINDIR "SysWOW64\winmm.dll"
if (!(Test-Path -LiteralPath $systemWinmm)) {
    $systemWinmm = Join-Path $env:WINDIR "System32\winmm.dll"
}
Copy-Item -LiteralPath $systemWinmm -Destination $realTarget -Force
Copy-Item -LiteralPath $resolvedDll -Destination $target -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
$realHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $realTarget).Hash
Write-Output "Installed $target"
Write-Output "Installed $realTarget"
Write-Output "SHA256 $hash"
Write-Output "REAL_SHA256 $realHash"

