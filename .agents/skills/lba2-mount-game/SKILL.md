---
name: lba2-mount-game
description: "Mount the Little Big Adventure 2 runtime disc image for this repo on the Alcohol 120% E: virtual CD-ROM and verify the game can see it."
---

# LBA2 Mount Game

Use this skill when  you need to mount the LBA2 game disc, fix the CD prompt by mounting media, prepare the original Windows runtime CD, or verify the repo-local mixed-mode image is mounted.

This skill is repo-local to `D:\repos\reverse\littlebigreversing`. Do not install it globally.

## Canonical Mount

The original runtime probes the Alcohol 120% virtual CD-ROM at `E:`. Do not use Windows `Mount-DiskImage` as the primary path; it can mount to a different drive and the game will still miss the disc.

Use:

```powershell
$repo = 'D:\repos\reverse\littlebigreversing'
$cue = Join-Path $repo 'work\runtime_media\lba2_mixed_mode\LBA2_TWINSEN_mixed.cue'
$ax = 'C:\Program Files (x86)\Alcohol Soft\Alcohol 120\AxCmd.exe'

& $ax 'E:' "/M:$cue"
```

## Verification

After mounting, verify all of these:

```powershell
Get-CimInstance Win32_CDROMDrive |
  Where-Object { $_.Drive -eq 'E:' } |
  Select-Object Drive,Caption,MediaLoaded,VolumeName,DeviceID

Get-Volume -DriveLetter E |
  Select-Object DriveLetter,FileSystemLabel,DriveType,OperationalStatus,Size

Test-Path -LiteralPath 'E:\LBA2\VIDEO\VIDEO.HQR'
```

Expected result:

- `MediaLoaded=True`
- `VolumeName` or `FileSystemLabel` is `LBA2`
- `DriveType` is `CD-ROM`
- `OperationalStatus` is `OK`
- `E:\LBA2\VIDEO\VIDEO.HQR` exists

## Known Traps

- `E:` may exist but be empty: `MediaLoaded=False`, `Size=0`. Run the Alcohol `AxCmd.exe` mount command above.
- The repo has notes showing a Windows-mounted image on a different drive is insufficient for the original runtime.
- Mounting the image only proves the filesystem side. If the game still shows the CD prompt, investigate MCI/Redbook readiness separately.
