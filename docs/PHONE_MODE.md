# Phone Mode

Use this repo convention when the user says they are on their phone or asks for phone mode.

## Contract

- Keep Codex updates concise.
- Avoid pasting large logs unless requested.
- Prefer visual artifacts when they help review.
- Send Slack only for completion, blockers, or review links.
- Serve repo-local artifacts on port `8876`.
- Keep shared pages mobile-first and minimal.
- Compress screenshots before sharing links.
- Keep commands, command output, and conclusions as readable text reports, not screenshots.

## Artifact Convention

- Share directory: `work/codex_phone_share/`
- Static server: `python tools/phone_share.py serve`
- Phone URL helper: `python tools/phone_share.py url`
- Main page: `work/codex_phone_share/index.html`

The server fails fast if port `8876` is occupied. Stop the conflicting service instead of silently changing ports.

## Screenshot Rules

- Use screenshots only for visual state the user cannot inspect from the phone, such as in-game windows, viewer output, rendered pages, or debugger panels where layout matters.
- Do not publish commands, logs, or command output as images. Put those in the Report section with `phone_share.py report`.
- UI, web, and docs: prefer mobile-width screenshots, crop to the relevant area when practical, then compress.
- Game/runtime: capture the full game window by default, then compress. Do not crop the game viewport unless explicitly requested.
- Debugger/tools: crop to the relevant panel unless the whole layout matters.

## Minimal Workflow

```powershell
python tools/phone_share.py init --clear --title "Viewer smoke" --status in_progress --note "Starting phone-mode review."
python tools/phone_share.py report --heading "Commands" --body "py -3 .\scripts\verify_viewer.py --fast`nPASS"
python tools/phone_share.py image .\work\screenshot.png --kind game --caption "Full game window" --status needs_review
python tools/phone_share.py serve
```

Set `CODEX_PHONE_SHARE_HOST` if the detected Tailscale address is not the URL the phone should use.
