# Decision-Clean Collaboration Plan For `LM_DEFAULT` / `LM_END_SWITCH`

## Summary
- Objective: get enough original-runtime evidence to decide whether to reopen the decoder boundary for `LM_DEFAULT` (`0x74`) and `LM_END_SWITCH` (`0x76`), without overcommitting to full interpreter semantics.
- Split the problem in two:
  - Decoder proof: byte width, control-flow role, and whether these bytes must be recognized structurally.
  - Runtime proof: whether either opcode has executable behavior beyond being a structural marker.
- Evidence priority: original Windows runtime through the bounded Frida tracer first, then detached `cdb` sessions on the same live process, then `Ghidra`, then local asset slices; `idajs` is only for repro/synthetic experiments, and `lba2remake` is only a hypothesis source.

## Collaboration Workflow
1. **Gate 1: Static dispatch proof in `Ghidra`**
- You locate the original `DoLife` dispatch, `DoFuncLife`, `DoTest`, the current-object struct, and the switch-state field.
- I map those findings against the known opcode grammar from the repo and produce a probe sheet with exact opcodes and expected pointer behavior.
- Required output:
  - dispatch function address
  - whether `0x74` and `0x76` have explicit dispatch cases
  - address/offset for current object, `PtrLife`, current script pointer/offset, and cached switch value/type
- Decision rule:
  - If explicit `0x74` or `0x76` cases exist, dynamic tracing must explain those handlers directly.
  - If no explicit cases exist, dynamic tracing focuses on whether execution ever lands on those bytes or only jumps around them.

2. **Gate 2: Deterministic repro setup**
- You prepare one reproducible entry path per probe case in the original game, using normal saves or `idajs` only to reach the target scene/actor reliably.
- I keep the target set minimal and ordered by discriminating power.
- Probe order:
  - scene `5` hero (`LM_END_SWITCH` shortest case)
  - scene `11` object `12` (`LM_DEFAULT` shortest case)
  - scene `11` object `18` (`LM_END_SWITCH` short object case)
  - scene `2` hero (mixed switch/default/end-switch case)
  - scene `44` only if ambiguity remains
- Required output:
  - save or steps to reach each target
  - how to identify the active actor/object in the debugger
  - confirmation that the same script tick can be hit repeatedly

3. **Gate 3: Attribution-first detached `cdb` tracing**
- You keep the Frida-established repro loop intact, start the repo-local detached `cdb` server on the already-running process, and trace one hit at a time from the dispatch site instead of from generic opcode scans.
- I decode each trace row against the local raw bytes and tell you exactly what the next probe should be.
- For every captured hit, record:
  - scene entry and owner (`hero` or object index)
  - object pointer
  - `PtrLife` base
  - current script pointer before fetch
  - opcode byte
  - script pointer after step
  - jump target if a branch occurs
  - cached switch value and cached type before/after
- Mandatory trace points:
  - dispatch entry
  - after opcode fetch
  - jump assignment for `CASE`, `OR_CASE`, and `BREAK`
  - any code path that changes the switch cache or clears it
- Canonical operator flow:
  - bootstrap a WinDbg/CDB remote session out-of-band on the already-running target
  - `open_windbg_remote(connection_string=...)`
  - `run_windbg_cmd(command="...")`
  - `send_ctrl_break(connection_string=...)` when a fresh break-in is needed
  - `close_windbg_remote(connection_string=...)` when the session is done

4. **Gate 4: Fast falsification tests**
- We do not try to “confirm the hypothesis”; we try to break it.
- Questions each probe must answer:
  - Does execution ever land on `0x74` or `0x76` as the current opcode?
  - If it lands there, does the script pointer advance by exactly one byte or consume more?
  - Does any handler read trailing bytes after `0x74` or `0x76`?
  - Does `BREAK` jump to the `END_SWITCH` byte or the byte after it?
  - Does reaching `0x76` change live switch state?
- Success pattern for decoder-only reopening:
  - `0x74` and `0x76` are proven zero-width markers in live execution or proven safe one-byte structural tokens with no hidden operand reads.
- Failure pattern:
  - any hidden operand read
  - inability to attribute hits to a known scene/owner/offset
  - ambiguous pointer movement

5. **Gate 5: Optional synthetic isolation**
- Use `idajs` only if natural probes leave one narrow ambiguity.
- Synthetic experiments are limited to:
  - default taken
  - default not taken
  - break taken
  - case fallthrough without break
  - one nested-switch attempt
- Each synthetic script must isolate one question only.
- `lba2remake` is not used for proof, only for candidate script shape.

## Decision Rules
- **Reopen decoder boundary only if all decoder facts are proven:**
  - exact byte width of `LM_DEFAULT`
  - exact byte width of `LM_END_SWITCH`
  - whether `BREAK` targets the marker byte or the byte after it
  - no hidden operand reads beyond the proven width
- **Do not reopen runtime semantics unless additionally proven:**
  - whether `LM_END_SWITCH` has an executable runtime action or is only structural
  - whether switch state is single-slot or nested
- **Default outcome if proof is partial:**
  - allow a decoder-only change later
  - keep interpreter/runtime support out of scope
  - keep the guarded runtime boundary closed

## Implementation Follow-Up If Proof Succeeds
- Decoder-only follow-up:
  - add structural support for `LM_DEFAULT` and `LM_END_SWITCH` in the Zig decoder with the exact proven byte width
  - add real-asset tests for scenes `5`, `11`, and `2`
  - keep runtime execution unsupported unless runtime semantics are separately proven
- Full runtime follow-up, only if separately proven:
  - implement switch-state behavior exactly as traced in the original runtime
  - use one per-object switch slot unless nested-switch traces prove otherwise

## Test Plan
- Static proof test: verify whether the original binary has explicit dispatch branches for `0x74` and `0x76`.
- Attribution test: obtain one unambiguous trace row for scene `5` hero and one for scene `11` object `12`.
- Width test: prove post-step pointer movement for `0x74` and `0x76`.
- Jump-target test: prove whether `BREAK` lands on or after `END_SWITCH`.
- Regression-ready asset test after proof: local decoder must fully scan the selected life blobs without hitting unsupported opcode errors.

## Assumptions And Defaults
- Primary platform is the original Windows runtime with staged Frida plus WinDbg MCP control over an existing remote session; `DOSBox-X` is out of scope unless Windows tracing fails.
- We optimize for the smallest decisive evidence, not exhaustive reverse engineering.
- `scene 44` is deferred because it is large and noisy.
- The first acceptable success state is decoder proof, not full interpreter proof.
