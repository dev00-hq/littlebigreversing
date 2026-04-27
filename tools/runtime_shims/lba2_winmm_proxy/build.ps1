param(
    [string]$OutDir = "$PSScriptRoot\..\..\..\build\runtime_shims\lba2_winmm_proxy"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$source = Join-Path $PSScriptRoot "winmm_proxy.c"
$def = Join-Path $PSScriptRoot "winmm_proxy.def"
$outDll = Join-Path $OutDir "winmm.dll"

cl.exe /nologo /LD /W4 /O2 /Fo:$OutDir\ /Fe:$outDll $source $def user32.lib /link /MACHINE:X86 /NOLOGO
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output $outDll


