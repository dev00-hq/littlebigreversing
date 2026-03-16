# Study: Feasibility of Using This Repo for `forum.magicball.net`

Date: February 12, 2026

## Scope

Question: can this repository (`discourse-downloader`) be adapted with reasonably easy changes to scrape `https://forum.magicball.net/` using username/password, or is it better to build a new tool?

## What I Tested

- Reviewed the current script in `discourse-downloader`.
- Confirmed target platform details from live responses:
  - `https://forum.magicball.net/` returns `meta generator: Discourse 3.5.3`.
  - `X-Discourse-Route` headers are present.
- Ran this tool successfully against live forum data:
  - Topic flow: `./discourse-downloader -m https://forum.magicball.net/t/gerenuk-how-rabbibunnies-look-like-in-real-life/30241`
  - Category flow: `./discourse-downloader -m https://forum.magicball.net/c/administration/6`
- Verified login mechanics:
  - Login UI has username/password fields (via `agent-browser` on `/login`).
  - CSRF endpoint works: `GET /session/csrf` returns JSON token.
  - Session login endpoint works: `POST /session.json` with CSRF and form credentials returns auth error JSON for invalid creds (expected), proving the flow is available.

## Current Repo Capability

The current script already works for public Discourse topic/category scraping and output to HTML or text.

Strengths:
- No heavy dependencies.
- Topic and category paths are implemented and working against this target.
- Supports optional Discourse API key auth (`api_key` + `api_user`).

Limitations relevant to username/password:
- No session/cookie handling.
- No CSRF fetch + login POST flow.
- Uses `open-uri` directly (not ideal for authenticated multi-request sessions).
- Credentials handling is API-key oriented only.
- Minor quality issues:
  - `File.file?(CONFIG_FILE)` is checked even when `-c` points elsewhere.
  - URL parsing is somewhat brittle (regex assumptions).

## Is Username/Password Support a "Reasonably Easy" Change?

Yes, for this repository and this target forum, it is a reasonably easy extension, not a full rewrite scenario.

Why:
- Discourse standard login endpoints are available on this forum.
- Existing scraping logic already works; auth can be added as a thin client layer.
- No custom anti-bot challenge was encountered in these checks (though plugins like hCaptcha exist and could still trigger under some conditions).

## Minimal Change Plan (Recommended)

1. Replace direct `open(...)` calls with helper methods backed by `Net::HTTP` + cookie jar.
2. Add optional CLI flags:
   - `--username`
   - `--password` (and/or `--password-env VAR`)
3. Implement login flow when username/password is provided:
   - GET `/session/csrf` (JSON)
   - POST `/session.json` with CSRF + credentials
   - Persist cookies in memory for subsequent requests
4. Route all topic/category/raw fetches through the authenticated client.
5. Keep existing API-key mode and anonymous mode for backward compatibility.
6. Fix config path check bug (`options.config_file` vs constant).

Estimated effort:
- ~0.5 to 1.5 days including smoke testing.

## Rewrite vs Extend: Recommendation

Recommendation: **extend this tool** rather than writing a new one.

Rationale:
- Core Discourse scraping logic is already functional on this exact site.
- Auth support is additive and localized.
- A rewrite would mainly re-implement logic that already works.

When a rewrite would make sense instead:
- You need a broader crawler (attachments, user graphs, private messages, incremental sync, retries/backoff, full observability).
- You want long-term maintainability with tests and modular architecture from day one.

## Risk Notes

- Private/restricted content behavior was not fully testable without valid credentials.
- If this forum enables stricter bot protections later (captcha/challenges), scripted login may require fallback strategies.
- Output is currently file-per-topic and can overwrite existing files with same topic id.

## Bottom Line

For `forum.magicball.net` (currently Discourse), this repo is a good base.  
Adding username/password login is feasible with reasonably easy, contained changes.  
A full rewrite is not necessary unless your scope is much larger than topic/category export.
