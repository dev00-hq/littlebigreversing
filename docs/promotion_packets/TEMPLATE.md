# <Packet Title>

## Packet Identity

- `id`:
- `status`:
- `evidence_class`:
- `canonical_runtime`:

## Exact Seam Identity

- room/load:
- source:
- destination:
- trigger:

## Decode Evidence

Describe the decoded structure and cite the command, fixture, source, or asset evidence.

## Original Runtime Live Evidence

Describe the original-runtime run and the observed runtime-owned signal. If the seam is not live-proven, state the missing signal.

## Runtime Invariant

State the exact invariant being promoted, rejected, or kept as decode-only.

## Positive Test

Name the checked-in test or planned test that proves the promoted behavior.

## Negative Test

Name the checked-in test or planned test that prevents over-promotion or wrong-source behavior.

## Reproduction Command

```powershell
<command>
```

## Failure Mode

State the fail-fast diagnostic or rejection behavior when this seam is not live-proven.

## Docs And Memory

List docs and memory files updated by this packet.

## Old Hypothesis Handling

State which old hypothesis was deleted, downgraded, or left as a candidate.

## Revision History

- YYYY-MM-DD: Initial packet.
