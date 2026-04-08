# LM Callsite Attribution Plan

This note owns the plan for callsite-tagged live attribution inside `LM_TASKS/`.

It does not widen the decoder or runtime boundary.
It adds a proof-oriented way to tell repeated helper invocations apart, similar to tagging repeated RNG draws by static callsite in a porting workflow.

Canonical repo/product direction still lives in:

- [project_brief.md](/D:/repos/reverse/littlebigreversing/docs/codex_memory/project_brief.md)
- [current_focus.md](/D:/repos/reverse/littlebigreversing/docs/codex_memory/current_focus.md)

## Goal

For live LM evidence, distinguish repeated calls to the same helper by the exact static place that made the call.

The first targets are:

- `DoFuncLife @ 0x0041F0A8`
- `DoTest @ 0x0041FE30`

Why this matters:

- repeated helper hits are currently easy to count but hard to name
- scene-11 and Tavern traces can contain multiple helper invocations that otherwise look identical
- a callsite tag lets us map a live helper invocation back to a specific decompile location and a specific `PtrPrg` fetch window
- that makes later port annotations more precise without claiming new semantics

## Decision

Use one canonical implementation path:

- static callsite extraction in `Ghidra`
- live caller capture in `Frida`
- optional `CDB` or WinDbg MCP spot-checks only for verification

Do not make Binary Ninja Free the execution owner for this feature.

Reasons:

- the repo already has checked-in Ghidra scripting and recovered interpreter addresses
- the repo already has a structured Frida tracer and a Frida-to-CDB bootstrap
- this keeps one current-state toolchain instead of adding a second automation owner

Relevant current files:

- [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)
- [ListXrefsTo.java](/D:/repos/reverse/littlebigreversing/work/ghidra_scripts/ListXrefsTo.java)
- [agent.js](/D:/repos/reverse/littlebigreversing/tools/life_trace/agent.js)
- [trace_life.py](/D:/repos/reverse/littlebigreversing/tools/life_trace/trace_life.py)
- [lba2_frida_cdb_bootstrap.py](/D:/repos/reverse/littlebigreversing/tools/lba2_frida_cdb_bootstrap.py)

## Canonical Data Model

The join key should be the module-relative fallthrough address after the `call`.

Static export fields:

- `callee_name`
- `callee_address`
- `within_function`
- `within_entry`
- `call_instruction`
- `caller_static`
- `caller_static_rel`
- `call_index`

Runtime event fields:

- `callee_name`
- `caller_static_live`
- `caller_static_rel`
- `thread_id`
- `object_index`
- `ptr_life`
- `ptr_prg`
- `ptr_prg_offset`
- `opcode`

Enriched event fields:

- `within_function`
- `within_entry`
- `call_instruction`
- `call_index`
- `callsite_status`

`caller_static` is the fallthrough PC, not the address of the `call` instruction itself.
The static export should preserve both fields so the naming stays unambiguous.

## Phases

### Phase 1: Static Callsite Export

Add a focused Ghidra exporter, likely:

- `work/ghidra_scripts/ExportCallsitesToJson.java`

Inputs:

- one or more callee addresses
- optional `within` filter

Outputs:

- JSONL under `work/ghidra_projects/callsites/`

Initial export set:

- callers of `0x0041F0A8`
- callers of `0x0041FE30`

Requirements:

- emit one record per callsite
- sort by containing function and call address for stable output
- compute `call_index` within each containing function and callee pair
- fail fast if the requested callee address has no containing symbol or no call references

### Phase 2: Live Caller Capture In Frida

Extend the Frida agent to record helper-entry caller addresses for the targeted callees.

Likely shape:

- attach to `absolute(offsets.doFuncLife)`
- attach to `absolute(offsets.doTest)`
- on entry, record `this.returnAddress`
- normalize to module-relative `caller_static_rel`

Emit a structured event, for example:

- `kind = helper_callsite`

Each emitted event should keep the existing LM context:

- current object index
- `PtrLife`
- current `PtrPrg`
- current opcode byte
- current `PtrPrg` offset

Guardrails:

- keep existing Scene11Pair and Tavern behavior intact
- do not replace the current `trace`, `window_trace`, or `do_life_return` evidence surface
- add helper-callsite events as additive evidence

### Phase 3: Host-Side Join And Annotation

Extend the Python driver to optionally load the static callsite map and enrich runtime events before they are written.

Likely additions:

- a `--callsites-jsonl` argument in [trace_life.py](/D:/repos/reverse/littlebigreversing/tools/life_trace/trace_life.py)
- host-side lookup by `callee_name` plus `caller_static_rel`

Canonical behavior:

- if a runtime helper event matches the static map, write the enriched fields into the JSONL
- if a runtime helper event does not match, emit `callsite_status = unmapped`
- for structured verification runs, prefer explicit failure or a terminal `unmapped_callsite` result over silent fallback

This repo should not add a compatibility path that quietly drops the attribution field.

### Phase 4: Verification

Use existing LM lanes as the acceptance paths.

Primary proof runs:

- Tavern baseline for `LM_END_SWITCH`
- Scene11Pair for object `12` `0x74 @ 38`
- Scene11Pair for object `18` `0x76 @ 84`

Verification goals:

- repeated `DoFuncLife` hits in one lane become distinguishable by `call_index`
- repeated `DoTest` hits in one lane become distinguishable by `call_index`
- `caller_static_rel` remains stable across ASLR because the join uses module-relative offsets

Optional debugger spot-check:

- break at helper entry in WinDbg
- read the x86 return address from `poi(@esp)`
- confirm it matches the Frida-captured `caller_static_live`

Keep this as a spot-check only, not the canonical logging surface.

## Deliverables

- new Ghidra callsite exporter script
- static JSONL callsite map for `DoFuncLife` and `DoTest`
- Frida helper-callsite runtime events
- Python-side enrichment path for those runtime events
- one checked-in LM note or artifact reference showing the first successful enriched run

## Acceptance Criteria

This plan is complete when all of the following are true:

1. A static export exists for `DoFuncLife` and `DoTest` callsites in the current `LBA2.EXE`.
2. A live Frida run emits helper-callsite events with module-relative caller addresses.
3. The Python driver can enrich those events with `within_function` and `call_index`.
4. At least one Tavern artifact and one scene-11 artifact show helper calls that are distinguishable by callsite.
5. Unknown callsites surface as explicit diagnostics instead of silently disappearing.

## Risks And Traps

- Frida captures the return address, not the `call` instruction address.
- ASLR makes absolute addresses unstable, so joins must use module-relative offsets.
- Nested helper calls can occur on multiple threads, so the runtime event must always keep `thread_id`.
- Late attach can miss early helper calls and make a trace look incomplete.
- Static xrefs can include non-call references; the exporter must filter for actual callsites.

## Non-Goals

- proving new opcode semantics
- widening the guarded decoder or runtime boundary
- adding Binary Ninja Free as a second automation path
- reviving x64dbg or shell-managed `cdb` as a parallel workflow
- building a generic all-functions callsite framework before the `DoFuncLife` and `DoTest` proof works

## Recommended First Slice

Take the smallest useful path first:

1. Export static callsites for `DoFuncLife` and `DoTest`.
2. Emit raw `helper_callsite` events from Frida with `this.returnAddress`.
3. Join on module-relative `caller_static_rel`.
4. Prove the enrichment on one Tavern run before widening to Scene11Pair.

If that first slice fails, fix the join contract before adding more targets or more tracer modes.
