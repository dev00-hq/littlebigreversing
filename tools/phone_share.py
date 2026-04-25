from __future__ import annotations

import argparse
import html
import json
import os
import shutil
import socket
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

try:
    from PIL import Image
except ModuleNotFoundError:  # pragma: no cover - exercised by real CLI diagnostics.
    Image = None  # type: ignore[assignment]


DEFAULT_PORT = 8876
DEFAULT_SHARE_DIR = Path("work/codex_phone_share")
MANIFEST_NAME = "manifest.json"
INDEX_NAME = "index.html"
STATUS_VALUES = ("in_progress", "pass", "blocked", "needs_review")
KIND_VALUES = ("ui", "game", "debug")


@dataclass(frozen=True)
class Paths:
    repo_root: Path
    share_dir: Path
    manifest: Path
    index: Path


def repo_root_from_here() -> Path:
    return Path(__file__).resolve().parents[1]


def default_paths(share_dir: Path | None = None) -> Paths:
    root = repo_root_from_here()
    share = share_dir or root / DEFAULT_SHARE_DIR
    if not share.is_absolute():
        share = root / share
    return Paths(root, share, share / MANIFEST_NAME, share / INDEX_NAME)


def read_manifest(paths: Paths) -> dict:
    if not paths.manifest.exists():
        return {
            "title": "Codex phone share",
            "status": "in_progress",
            "notes": [],
            "reports": [],
            "images": [],
            "updated_at": None,
        }
    return json.loads(paths.manifest.read_text(encoding="utf-8"))


def write_manifest(paths: Paths, manifest: dict) -> None:
    paths.share_dir.mkdir(parents=True, exist_ok=True)
    manifest["updated_at"] = datetime.now().isoformat(timespec="seconds")
    paths.manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    render_index(paths, manifest)


def render_index(paths: Paths, manifest: dict) -> None:
    title = html.escape(manifest.get("title") or "Codex phone share")
    status = html.escape(manifest.get("status") or "in_progress")
    updated = html.escape(manifest.get("updated_at") or "not written yet")
    notes = [str(note) for note in manifest.get("notes", []) if str(note).strip()]
    reports = list(manifest.get("reports", []))
    images = list(manifest.get("images", []))

    note_items = "\n".join(f"<li>{html.escape(note)}</li>" for note in notes)
    if not note_items:
        note_items = "<li>No notes yet.</li>"

    report_items = []
    for report in reports:
        heading = html.escape(str(report.get("heading") or "Report"))
        body = html.escape(str(report.get("body") or ""))
        report_items.append(
            f"""
            <article class="report">
              <h3>{heading}</h3>
              <pre>{body}</pre>
            </article>
            """
        )
    report_html = "\n".join(report_items) or '<p class="empty">No report entries yet.</p>'

    image_items = []
    for image in images:
        rel = html.escape(str(image["file"]))
        caption = html.escape(str(image.get("caption") or image.get("kind") or "screenshot"))
        kind = html.escape(str(image.get("kind") or "ui"))
        size = html.escape(str(image.get("size") or ""))
        image_items.append(
            f"""
            <figure class="shot shot-{kind}">
              <a href="{rel}"><img src="{rel}" alt="{caption}"></a>
              <figcaption>{caption}<span>{kind} screenshot{size}</span></figcaption>
            </figure>
            """
        )
    image_html = "\n".join(image_items) or '<p class="empty">No screenshots published yet.</p>'

    paths.index.write_text(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #f7f7f4;
      --fg: #191b1f;
      --muted: #606770;
      --line: #d8dadf;
      --accent: #0f766e;
      --panel: #ffffff;
    }}
    @media (prefers-color-scheme: dark) {{
      :root {{
        --bg: #111318;
        --fg: #f0f2f5;
        --muted: #a7adb7;
        --line: #30343b;
        --accent: #2dd4bf;
        --panel: #171a21;
      }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: var(--bg);
      color: var(--fg);
      font: 16px/1.45 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }}
    main {{
      width: min(100%, 760px);
      margin: 0 auto;
      padding: 18px 14px 36px;
    }}
    header {{
      border-bottom: 1px solid var(--line);
      padding-bottom: 14px;
      margin-bottom: 18px;
    }}
    h1 {{
      margin: 0 0 8px;
      font-size: 1.4rem;
      letter-spacing: 0;
    }}
    .meta {{
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      align-items: center;
      color: var(--muted);
      font-size: 0.92rem;
    }}
    .status {{
      background: color-mix(in srgb, var(--accent) 16%, transparent);
      color: var(--accent);
      border: 1px solid color-mix(in srgb, var(--accent) 38%, transparent);
      border-radius: 999px;
      padding: 2px 9px;
      font-weight: 650;
    }}
    section {{
      margin-top: 20px;
    }}
    h2 {{
      margin: 0 0 8px;
      font-size: 1rem;
      letter-spacing: 0;
    }}
    ul {{
      margin: 0;
      padding-left: 20px;
    }}
    .reports {{
      display: grid;
      gap: 12px;
    }}
    .report {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }}
    .report h3 {{
      margin: 0;
      padding: 10px 12px;
      border-bottom: 1px solid var(--line);
      font-size: 0.95rem;
      letter-spacing: 0;
    }}
    pre {{
      margin: 0;
      padding: 12px;
      overflow-x: auto;
      white-space: pre-wrap;
      word-break: break-word;
      font: 0.88rem/1.4 ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace;
    }}
    .shots {{
      display: grid;
      gap: 16px;
    }}
    figure {{
      margin: 0;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }}
    img {{
      display: block;
      width: 100%;
      height: auto;
      background: #000;
    }}
    figcaption {{
      display: flex;
      justify-content: space-between;
      gap: 10px;
      padding: 10px 12px 4px;
      font-size: 0.95rem;
    }}
    figcaption span {{
      color: var(--muted);
      white-space: nowrap;
    }}
    a {{
      color: var(--accent);
    }}
    .empty {{
      color: var(--muted);
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <h1>{title}</h1>
      <div class="meta"><span class="status">{status}</span><span>updated {updated}</span></div>
    </header>
    <section>
      <h2>Notes</h2>
      <ul>
        {note_items}
      </ul>
    </section>
    <section>
      <h2>Report</h2>
      <div class="reports">
        {report_html}
      </div>
    </section>
    <section>
      <h2>Screenshots</h2>
      <div class="shots">
        {image_html}
      </div>
    </section>
  </main>
</body>
</html>
""",
        encoding="utf-8",
    )


def require_pillow() -> None:
    if Image is None:
        raise SystemExit(
            "Pillow is required for image compression. Run: py -3 -m pip install -r requirements.txt"
        )


def init_share(args: argparse.Namespace) -> None:
    paths = default_paths(args.share_dir)
    manifest = read_manifest(paths)
    manifest["title"] = args.title
    manifest["status"] = args.status
    if args.clear:
        manifest["notes"] = []
        manifest["reports"] = []
        manifest["images"] = []
        for child in paths.share_dir.glob("*"):
            if child.name not in {MANIFEST_NAME, INDEX_NAME}:
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
    if args.note:
        manifest.setdefault("notes", []).append(args.note)
    write_manifest(paths, manifest)
    print(paths.index)


def add_note(args: argparse.Namespace) -> None:
    paths = default_paths(args.share_dir)
    manifest = read_manifest(paths)
    manifest.setdefault("notes", []).append(args.note)
    if args.status:
        manifest["status"] = args.status
    write_manifest(paths, manifest)
    print(paths.index)


def add_report(args: argparse.Namespace) -> None:
    paths = default_paths(args.share_dir)
    manifest = read_manifest(paths)
    if args.file:
        if args.body:
            raise SystemExit("use either --body or --file for report text, not both")
        if not args.file.exists():
            raise SystemExit(f"report file not found: {args.file}")
        body = args.file.read_text(encoding="utf-8")
    else:
        body = args.body
    if not body.strip():
        raise SystemExit("report body is empty")
    manifest.setdefault("reports", []).append(
        {
            "heading": args.heading,
            "body": body,
        }
    )
    if args.status:
        manifest["status"] = args.status
    write_manifest(paths, manifest)
    print(paths.index)


def safe_stem(path: Path) -> str:
    allowed = []
    for char in path.stem.lower():
        allowed.append(char if char.isalnum() else "-")
    result = "".join(allowed).strip("-")
    return result or "screenshot"


def next_image_path(paths: Paths, source: Path) -> Path:
    shots_dir = paths.share_dir / "screenshots"
    shots_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return shots_dir / f"{stamp}-{safe_stem(source)}.webp"


def publish_image(args: argparse.Namespace) -> None:
    require_pillow()
    source = args.source.resolve()
    if not source.exists():
        raise SystemExit(f"image not found: {source}")

    paths = default_paths(args.share_dir)
    manifest = read_manifest(paths)
    out_path = next_image_path(paths, source)

    assert Image is not None
    max_width = args.max_width
    if max_width is None:
        max_width = 100000 if args.kind == "game" else 900
    with Image.open(source) as raw:
        image = raw.copy()
        image.thumbnail((max_width, 100000), Image.Resampling.LANCZOS)
        if image.mode not in ("RGB", "L"):
            background = Image.new("RGB", image.size, (255, 255, 255))
            if "A" in image.getbands():
                background.paste(image, mask=image.getchannel("A"))
            else:
                background.paste(image)
            image = background
        image.save(out_path, format="WEBP", quality=args.quality, method=6)
        width, height = image.size

    rel_path = out_path.relative_to(paths.share_dir).as_posix()
    manifest.setdefault("images", []).append(
        {
            "file": rel_path,
            "original": source.as_posix(),
            "kind": args.kind,
            "caption": args.caption or source.name,
            "size": f", {width}x{height}",
        }
    )
    if args.status:
        manifest["status"] = args.status
    write_manifest(paths, manifest)
    print(out_path)


def tailscale_host() -> str:
    explicit = os.environ.get("CODEX_PHONE_SHARE_HOST")
    if explicit:
        return explicit
    tailscale = shutil.which("tailscale")
    if tailscale:
        try:
            result = subprocess.run(
                [tailscale, "ip", "-4"],
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
            )
            first = result.stdout.splitlines()[0].strip()
            if first:
                return first
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, IndexError):
            pass
    return socket.gethostname()


def assert_port_free(host: str, port: int) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((host, port))
        except OSError as exc:
            raise SystemExit(
                f"port {port} is already in use; stop the existing service before starting phone share"
            ) from exc


def serve(args: argparse.Namespace) -> None:
    paths = default_paths(args.share_dir)
    paths.share_dir.mkdir(parents=True, exist_ok=True)
    manifest = read_manifest(paths)
    write_manifest(paths, manifest)
    assert_port_free(args.bind, args.port)

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *handler_args: object, **handler_kwargs: object) -> None:
            super().__init__(*handler_args, directory=str(paths.share_dir), **handler_kwargs)

    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    share_url = f"http://{tailscale_host()}:{args.port}/"
    local_url = f"http://127.0.0.1:{args.port}/"
    print(f"serving {paths.share_dir}")
    print(f"phone URL: {share_url}")
    print(f"local URL: {local_url}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


def print_url(args: argparse.Namespace) -> None:
    print(f"http://{tailscale_host()}:{args.port}/")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Phone-mode artifact sharing for Codex sessions.")
    parser.add_argument("--share-dir", type=Path, default=None, help=f"default: {DEFAULT_SHARE_DIR}")
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init", help="create or refresh the mobile-first index")
    init.add_argument("--title", required=True)
    init.add_argument("--status", choices=STATUS_VALUES, default="in_progress")
    init.add_argument("--note")
    init.add_argument("--clear", action="store_true", help="remove previous screenshots and notes")
    init.set_defaults(func=init_share)

    note = sub.add_parser("note", help="append a short note")
    note.add_argument("note")
    note.add_argument("--status", choices=STATUS_VALUES)
    note.set_defaults(func=add_note)

    report = sub.add_parser("report", help="append readable command output or a short report")
    report.add_argument("--heading", required=True)
    report.add_argument("--body", default="")
    report.add_argument("--file", type=Path)
    report.add_argument("--status", choices=STATUS_VALUES)
    report.set_defaults(func=add_report)

    image = sub.add_parser("image", help="compress and publish a screenshot")
    image.add_argument("source", type=Path)
    image.add_argument("--kind", choices=KIND_VALUES, default="ui")
    image.add_argument("--caption")
    image.add_argument("--status", choices=STATUS_VALUES)
    image.add_argument("--quality", type=int, default=78)
    image.add_argument(
        "--max-width",
        type=int,
        default=None,
        help="default: 900 for ui/debug, unchanged width for game",
    )
    image.set_defaults(func=publish_image)

    server = sub.add_parser("serve", help="serve the share folder on the repo phone-mode port")
    server.add_argument("--bind", default="0.0.0.0")
    server.add_argument("--port", type=int, default=DEFAULT_PORT)
    server.set_defaults(func=serve)

    url = sub.add_parser("url", help="print the Tailscale/share URL")
    url.add_argument("--port", type=int, default=DEFAULT_PORT)
    url.set_defaults(func=print_url)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
