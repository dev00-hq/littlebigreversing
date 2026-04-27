from __future__ import annotations

import socket
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import phone_share


class PhoneShareTest(unittest.TestCase):
    def paths(self) -> phone_share.Paths:
        root = Path(tempfile.mkdtemp())
        return phone_share.Paths(root, root / "share", root / "share" / "manifest.json", root / "share" / "index.html")

    def test_render_index_is_mobile_first_and_minimal(self) -> None:
        paths = self.paths()
        manifest = {
            "title": "Viewer smoke",
            "status": "needs_review",
            "updated_at": "2026-04-25T12:00:00",
            "notes": ["Check the scene load."],
            "reports": [
                {
                    "heading": "Commands",
                    "body": "py -3 tools\\phone_share.py url\nhttp://100.97.1.106:8876/",
                }
            ],
            "images": [
                {
                    "file": "screenshots/viewer.webp",
                    "original": "D:/tmp/viewer.png",
                    "kind": "game",
                    "caption": "Full game window",
                    "size": ", 816x639",
                }
            ],
        }

        paths.share_dir.mkdir(parents=True)
        phone_share.render_index(paths, manifest)

        html = paths.index.read_text(encoding="utf-8")
        self.assertIn('<meta name="viewport" content="width=device-width, initial-scale=1">', html)
        self.assertIn("width: min(100%, 760px)", html)
        self.assertIn("Full game window", html)
        self.assertIn("needs_review", html)
        self.assertIn("py -3 tools\\phone_share.py url", html)
        self.assertIn("<pre>", html)
        self.assertNotIn("D:/tmp/viewer.png", html)

    def test_manifest_write_renders_index(self) -> None:
        paths = self.paths()
        phone_share.write_manifest(
            paths,
            {
                "title": "Task",
                "status": "pass",
                "notes": [],
                "reports": [],
                "images": [],
            },
        )

        self.assertTrue(paths.manifest.exists())
        self.assertTrue(paths.index.exists())
        self.assertIn("Task", paths.index.read_text(encoding="utf-8"))

    def test_add_report_renders_readable_text_not_image(self) -> None:
        paths = self.paths()
        args = type(
            "Args",
            (),
            {
                "share_dir": paths.share_dir,
                "heading": "Command result",
                "body": "py -3 -m unittest tools.test_phone_share\nOK",
                "file": None,
                "status": "pass",
            },
        )()

        phone_share.add_report(args)

        html = paths.index.read_text(encoding="utf-8")
        manifest = phone_share.read_manifest(paths)
        self.assertEqual(manifest["reports"][0]["heading"], "Command result")
        self.assertIn("py -3 -m unittest tools.test_phone_share", html)
        self.assertIn("<pre>", html)
        self.assertNotIn("<img src=", html)

    def test_assert_port_free_fails_fast_when_busy(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            sock.listen(1)
            port = sock.getsockname()[1]
            with self.assertRaises(SystemExit) as raised:
                phone_share.assert_port_free("127.0.0.1", port)

        self.assertIn("already in use", str(raised.exception))

    @unittest.skipIf(phone_share.Image is None, "Pillow not installed")
    def test_publish_image_compresses_to_webp(self) -> None:
        from PIL import Image

        paths = self.paths()
        source = paths.repo_root / "source.png"
        Image.new("RGB", (1200, 800), (20, 40, 80)).save(source)

        args = type(
            "Args",
            (),
            {
                "source": source,
                "share_dir": paths.share_dir,
                "kind": "ui",
                "caption": "UI crop",
                "status": "needs_review",
                "quality": 70,
                "max_width": 900,
            },
        )()

        phone_share.publish_image(args)

        manifest = phone_share.read_manifest(paths)
        output = paths.share_dir / manifest["images"][0]["file"]
        self.assertEqual(output.suffix, ".webp")
        self.assertTrue(output.exists())
        with Image.open(output) as compressed:
            self.assertEqual(compressed.size, (900, 600))

    @unittest.skipIf(phone_share.Image is None, "Pillow not installed")
    def test_publish_game_image_keeps_window_size_by_default(self) -> None:
        from PIL import Image

        paths = self.paths()
        source = paths.repo_root / "game.png"
        Image.new("RGB", (1024, 768), (10, 20, 30)).save(source)

        args = type(
            "Args",
            (),
            {
                "source": source,
                "share_dir": paths.share_dir,
                "kind": "game",
                "caption": "Full game window",
                "status": None,
                "quality": 70,
                "max_width": None,
            },
        )()

        phone_share.publish_image(args)

        manifest = phone_share.read_manifest(paths)
        output = paths.share_dir / manifest["images"][0]["file"]
        with Image.open(output) as compressed:
            self.assertEqual(compressed.size, (1024, 768))

    @unittest.skipIf(phone_share.Image is None, "Pillow not installed")
    def test_publish_game_image_ignores_bad_alpha_channel(self) -> None:
        from PIL import Image

        paths = self.paths()
        source = paths.repo_root / "game_bad_alpha.png"
        image = Image.new("RGBA", (16, 16), (180, 60, 40, 0))
        image.save(source)

        args = type(
            "Args",
            (),
            {
                "source": source,
                "share_dir": paths.share_dir,
                "kind": "game",
                "caption": "Bad alpha game capture",
                "status": None,
                "quality": 100,
                "max_width": None,
            },
        )()

        phone_share.publish_image(args)

        manifest = phone_share.read_manifest(paths)
        output = paths.share_dir / manifest["images"][0]["file"]
        with Image.open(output) as compressed:
            pixel = compressed.convert("RGB").getpixel((0, 0))

        self.assertGreater(pixel[0], 120)
        self.assertLess(pixel[1], 120)
        self.assertLess(pixel[2], 120)


if __name__ == "__main__":
    unittest.main()
