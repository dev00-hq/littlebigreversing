from __future__ import annotations

import argparse
import tkinter as tk
from pathlib import Path
from typing import Any

from debug_compass import describe_beta
from heading_inject import DEFAULT_FRIDA_REPO, DEFAULT_PROCESS_NAME, HeadingInjector
from life_trace_windows import WindowCapture


DEFAULT_POLL_MS = 500


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Live sidecar coordinate HUD for original-runtime LBA2.EXE."
    )
    target = parser.add_mutually_exclusive_group(required=False)
    target.add_argument("--attach-pid", type=int, help="Attach to an already running LBA2.EXE pid.")
    target.add_argument(
        "--process-name",
        default=DEFAULT_PROCESS_NAME,
        help="Exact process name to attach to when --attach-pid is not provided.",
    )
    parser.add_argument(
        "--frida-repo-root",
        default=str(DEFAULT_FRIDA_REPO),
        help="Frida repo root containing build/install-root.",
    )
    parser.add_argument(
        "--poll-ms",
        type=int,
        default=DEFAULT_POLL_MS,
        help="Polling interval in milliseconds.",
    )
    parser.add_argument(
        "--always-on-top",
        action="store_true",
        help="Keep the HUD window above other windows.",
    )
    parser.add_argument(
        "--follow-window",
        action="store_true",
        help="Anchor the HUD beside the LBA2 window when possible.",
    )
    parser.add_argument(
        "--offset-x",
        type=int,
        default=16,
        help="Horizontal offset used with --follow-window.",
    )
    parser.add_argument(
        "--offset-y",
        type=int,
        default=0,
        help="Vertical offset used with --follow-window.",
    )
    parser.add_argument("--target-x", type=int, help="Initial target X coordinate.")
    parser.add_argument("--target-y", type=int, help="Initial target Y coordinate.")
    parser.add_argument("--target-z", type=int, help="Initial target Z coordinate.")
    return parser.parse_args()


def format_value(value: Any) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)


class LiveCoordsOverlay:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.injector = HeadingInjector(
            pid=args.attach_pid,
            process_name=args.process_name,
            frida_repo_root=Path(args.frida_repo_root),
        )
        self.capture = WindowCapture() if args.follow_window else None
        self.last_window_origin: tuple[int, int] | None = None

        self.root = tk.Tk()
        self.root.title("LBA2 Live Coords")
        self.root.resizable(False, False)
        self.root.configure(background="#111111")
        if args.always_on_top:
            self.root.attributes("-topmost", True)

        self.status_var = tk.StringVar(value="status: attaching")
        self.vars: dict[str, tk.StringVar] = {
            "x": tk.StringVar(value="-"),
            "y": tk.StringVar(value="-"),
            "z": tk.StringVar(value="-"),
            "beta": tk.StringVar(value="-"),
            "degrees": tk.StringVar(value="-"),
            "heading": tk.StringVar(value="-"),
            "delta_x": tk.StringVar(value="-"),
            "delta_y": tk.StringVar(value="-"),
            "delta_z": tk.StringVar(value="-"),
            "delta_l1": tk.StringVar(value="-"),
        }
        self.target_vars: dict[str, tk.StringVar] = {
            "x": tk.StringVar(value="" if args.target_x is None else str(args.target_x)),
            "y": tk.StringVar(value="" if args.target_y is None else str(args.target_y)),
            "z": tk.StringVar(value="" if args.target_z is None else str(args.target_z)),
        }
        self._build_ui()
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def _build_ui(self) -> None:
        outer = tk.Frame(self.root, bg="#111111", padx=12, pady=10)
        outer.pack(fill=tk.BOTH, expand=True)

        status = tk.Label(
            outer,
            textvariable=self.status_var,
            anchor="w",
            bg="#111111",
            fg="#d7d7d7",
            font=("Consolas", 10, "bold"),
        )
        status.grid(row=0, column=0, columnspan=2, sticky="we", pady=(0, 8))

        for row_index, key in enumerate(("x", "y", "z", "beta", "degrees", "heading"), start=1):
            tk.Label(
                outer,
                text=f"{key.upper():>7}",
                anchor="e",
                bg="#111111",
                fg="#8ab4f8",
                font=("Consolas", 10, "bold"),
                width=8,
            ).grid(row=row_index, column=0, sticky="e", padx=(0, 8), pady=1)
            tk.Label(
                outer,
                textvariable=self.vars[key],
                anchor="w",
                bg="#111111",
                fg="#f1f3f4",
                font=("Consolas", 10),
                width=14,
            ).grid(row=row_index, column=1, sticky="w", pady=1)

        target_header = tk.Label(
            outer,
            text="Target",
            anchor="w",
            bg="#111111",
            fg="#d7d7d7",
            font=("Consolas", 10, "bold"),
        )
        target_header.grid(row=7, column=0, columnspan=2, sticky="we", pady=(10, 4))

        for row_index, key in enumerate(("x", "y", "z"), start=8):
            tk.Label(
                outer,
                text=f"T_{key.upper():>5}",
                anchor="e",
                bg="#111111",
                fg="#f28b82",
                font=("Consolas", 10, "bold"),
                width=8,
            ).grid(row=row_index, column=0, sticky="e", padx=(0, 8), pady=1)
            tk.Entry(
                outer,
                textvariable=self.target_vars[key],
                bg="#202124",
                fg="#f1f3f4",
                insertbackground="#f1f3f4",
                relief=tk.FLAT,
                font=("Consolas", 10),
                width=14,
            ).grid(row=row_index, column=1, sticky="w", pady=1)

        button_row = tk.Frame(outer, bg="#111111")
        button_row.grid(row=11, column=0, columnspan=2, sticky="we", pady=(8, 2))
        tk.Button(
            button_row,
            text="Teleport",
            command=self.teleport_to_target,
            bg="#1a73e8",
            fg="#ffffff",
            activebackground="#185abc",
            activeforeground="#ffffff",
            relief=tk.FLAT,
            font=("Consolas", 10, "bold"),
            padx=10,
            pady=3,
        ).pack(side=tk.LEFT)

        delta_header = tk.Label(
            outer,
            text="Delta (current - target)",
            anchor="w",
            bg="#111111",
            fg="#d7d7d7",
            font=("Consolas", 10, "bold"),
        )
        delta_header.grid(row=12, column=0, columnspan=2, sticky="we", pady=(10, 4))

        for row_index, key in enumerate(("delta_x", "delta_y", "delta_z", "delta_l1"), start=13):
            label = {
                "delta_x": "DX",
                "delta_y": "DY",
                "delta_z": "DZ",
                "delta_l1": "L1",
            }[key]
            tk.Label(
                outer,
                text=f"{label:>7}",
                anchor="e",
                bg="#111111",
                fg="#34a853",
                font=("Consolas", 10, "bold"),
                width=8,
            ).grid(row=row_index, column=0, sticky="e", padx=(0, 8), pady=1)
            tk.Label(
                outer,
                textvariable=self.vars[key],
                anchor="w",
                bg="#111111",
                fg="#f1f3f4",
                font=("Consolas", 10),
                width=14,
            ).grid(row=row_index, column=1, sticky="w", pady=1)

    def run(self) -> None:
        self.root.after(0, self.poll_once)
        self.root.mainloop()

    def close(self) -> None:
        try:
            self.injector.close()
        finally:
            self.root.destroy()

    def _set_detached(self, reason: str) -> None:
        self.status_var.set(f"status: {reason}")
        for key in self.vars:
            self.vars[key].set("-")

    def _parse_target(self, axis: str) -> int | None:
        raw = self.target_vars[axis].get().strip()
        if not raw:
            return None
        try:
            return int(raw)
        except ValueError:
            return None

    def teleport_to_target(self) -> None:
        targets = {axis: self._parse_target(axis) for axis in ("x", "y", "z")}
        if any(targets[axis] is None for axis in ("x", "y", "z")):
            self.status_var.set("status: invalid teleport target")
            return
        try:
            snapshot = self.injector.teleport_xyz(
                int(targets["x"]),
                int(targets["y"]),
                int(targets["z"]),
                sync_old_position=True,
            )
        except Exception as exc:
            self.injector.close()
            self._set_detached(f"teleport failed ({exc.__class__.__name__})")
            return
        self.status_var.set(
            f"status: teleported pid={self.injector.target_pid if self.injector.target_pid is not None else '?'}"
        )
        self._update_from_snapshot(snapshot)

    def _update_target_deltas(self, snapshot: dict[str, Any]) -> None:
        targets = {axis: self._parse_target(axis) for axis in ("x", "y", "z")}
        currents = {axis: snapshot.get(axis) for axis in ("x", "y", "z")}
        if any(targets[axis] is None for axis in ("x", "y", "z")):
            self.vars["delta_x"].set("-")
            self.vars["delta_y"].set("-")
            self.vars["delta_z"].set("-")
            self.vars["delta_l1"].set("-")
            return
        deltas: dict[str, int] = {}
        for axis in ("x", "y", "z"):
            current = currents[axis]
            if current is None:
                self.vars["delta_x"].set("-")
                self.vars["delta_y"].set("-")
                self.vars["delta_z"].set("-")
                self.vars["delta_l1"].set("-")
                return
            deltas[axis] = int(current) - int(targets[axis])
        self.vars["delta_x"].set(str(deltas["x"]))
        self.vars["delta_y"].set(str(deltas["y"]))
        self.vars["delta_z"].set(str(deltas["z"]))
        self.vars["delta_l1"].set(str(abs(deltas["x"]) + abs(deltas["y"]) + abs(deltas["z"])))

    def _update_from_snapshot(self, snapshot: dict[str, Any]) -> None:
        beta_debug = snapshot.get("beta_debug")
        if not isinstance(beta_debug, dict):
            beta_debug = describe_beta(int(snapshot["beta"]))

        self.status_var.set(
            f"status: attached pid={self.injector.target_pid if self.injector.target_pid is not None else '?'}"
        )
        self.vars["x"].set(format_value(snapshot.get("x")))
        self.vars["y"].set(format_value(snapshot.get("y")))
        self.vars["z"].set(format_value(snapshot.get("z")))
        self.vars["beta"].set(format_value(snapshot.get("beta")))
        self.vars["degrees"].set(format_value(beta_debug.get("degrees")))
        self.vars["heading"].set(format_value(beta_debug.get("heading")))
        self._update_target_deltas(snapshot)

    def _maybe_follow_window(self) -> None:
        if not self.capture or self.injector.target_pid is None:
            return
        window = self.capture.find_window(self.injector.target_pid)
        if window is None:
            return
        new_origin = (window.right + self.args.offset_x, window.top + self.args.offset_y)
        if new_origin != self.last_window_origin:
            self.root.geometry(f"+{new_origin[0]}+{new_origin[1]}")
            self.last_window_origin = new_origin

    def poll_once(self) -> None:
        try:
            snapshot = self.injector.snapshot()
        except Exception as exc:
            self.injector.close()
            self._set_detached(f"detached ({exc.__class__.__name__})")
        else:
            self._update_from_snapshot(snapshot)
            self._maybe_follow_window()
        finally:
            self.root.after(max(self.args.poll_ms, 50), self.poll_once)


def main() -> int:
    args = parse_args()
    overlay = LiveCoordsOverlay(args)
    overlay.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
