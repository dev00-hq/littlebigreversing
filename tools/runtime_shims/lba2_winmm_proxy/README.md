# LBA2 WinMM Proxy

This is the canonical no-Frida CD/MCI shim for the extracted original Windows `LBA2.EXE` runtime.

The game loads `winmm.dll` from its own directory before the system copy. This proxy forwards the static LBA2/MSS/Smacker WinMM imports to a renamed `winmm_real.dll`, while forcing the Redbook/MCI CD checks needed by classic startup:

- `MCI_OPEN` succeeds and returns a fake device id.
- `MCI_STATUS_MODE` returns `MCI_MODE_STOP`.
- `MCI_STATUS_NUMBER_OF_TRACKS` returns `2`.
- `MCI_STATUS_MEDIA_PRESENT` and `MCI_STATUS_READY` return `1`.
- fake-device `MCI_CLOSE`, `MCI_SET`, `MCI_STOP`, and `MCI_PLAY` succeed.

Build from repo root:

```powershell
py -3 scripts\dev-shell.py --arch x86 exec --cwd . -- powershell -NoProfile -ExecutionPolicy Bypass -File tools\runtime_shims\lba2_winmm_proxy\build.ps1
```

Install into the extracted runtime:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\runtime_shims\lba2_winmm_proxy\install.ps1
```

`install.ps1` copies the proxy to `work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\winmm.dll` and copies the system 32-bit WinMM DLL to `winmm_real.dll`. Existing `winmm.dll` files are backed up with a timestamp.

Set `LBA2_WINMM_PROXY_LOG=1` before launch to write `winmm_proxy.log` in the game directory.
