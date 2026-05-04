# Little Big Reversing

Reverse-engineering and port-planning workspace for Twinsen's Little Big Adventure 2.

Start here:

- `docs/LBA2_ZIG_PORT_PLAN.md` for the roadmap, phases, gates, and acceptance checks.
- `docs/codex_memory/current_focus.md` for active repo state, blockers, and next actions.
- `port/README.md` for the canonical Zig port workspace.
- `docs/promotion_packets/` for runtime/gameplay promotion evidence. Decoded or inferred seams are not canonical runtime behavior without a `live_positive` or `approved_exception` packet.

Canonical Codex context is loaded with:

```powershell
py -3 tools/codex_memory.py context
```

Generated files under `docs/codex_memory/generated/` are reproducible derived context, not startup truth.
