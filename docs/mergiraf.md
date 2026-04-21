# Mergiraf Setup

This repository supports a narrow Mergiraf pilot for `*.zig`, `*.json`, and `*.py` files only.

## Prerequisites

- `mergiraf` must be installed and available on `PATH`

## Git Setup

Run these commands once on your machine:

```powershell
git config --global merge.conflictStyle diff3
git config --global merge.mergiraf.name mergiraf
git config --global merge.mergiraf.driver "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L"
```

## Verify Attribute Resolution

These checks should report `merge: mergiraf`:

```powershell
git check-attr merge -- port/src/main.zig
git check-attr merge -- docs/ingame_keyboard_layout.json
git check-attr merge -- scripts/verify_viewer.py
```

These checks should keep the default merge behavior:

```powershell
git check-attr merge -- docs/LBA2_ZIG_PORT_PLAN.md
git check-attr merge -- docs/codex_memory/task_events.jsonl
git check-attr merge -- AGENTS.md
```

## Temporary Bypass

Temporarily disable Mergiraf for a merge operation with:

```sh
mergiraf=0 git merge <branch>
```

On PowerShell, use:

```powershell
$env:mergiraf = "0"
git merge <branch>
Remove-Item Env:mergiraf
```

## Supported Repo Policy

This repository does not support a global `* merge=mergiraf` policy.
If you have a wildcard Mergiraf rule in a global attributes file, remove or disable it before working in this repository.
