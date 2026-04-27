# Phase 5 187 Runtime Reassessment

This note covers the `inside dark monk1.LBA` runtime entry and the invalidated `187/187` zone `1` teleport probe.

## Verified Entry

- The original runtime launches through `LBA2.EXE SAVE\inside dark monk1.LBA`.
- The save header is `NumVersion=0xA4`, `NumCube=185`, save name `inside dark monk1`.
- In the current save-header convention, raw scene entry is `NumCube + 2 = 187`.
- The initial runtime pose is cube `185` at `(28647,2304,21741)`.

This proves the save is a cube-`185` entry associated with raw scene `187`; it does not by itself prove that arbitrary `187/187` decoded coordinates are safe to write into the live process.

## Invalidated Probe

The old probe teleported Twinsen to `(1536,256,4608)`, the center of decoded scene/background `187/187` zone `1`, without independently proving that coordinate frame was valid for the loaded runtime state.

The recorded run immediately snapped from the requested source coordinate to `(28416,2304,21760)` with:

- `new_cube = -1`
- `zones = []`
- no staged `NewPos`
- no observed target-zone membership
- a visible clover/life-loss indicator in the source screenshot

That is not a valid transition proof. It is consistent with an invalid teleport, fall/death, or safety reset back to a saved/start position.

## Counterfactual

`tools/fixtures/phase5_187_startcube_counterfactual.json` changed only `StartXCube` from `55` to `54`, but it used the same invalid source teleport. Because the run did not observe a real transition signal, it cannot prove or disprove the transition branch's causal model.

## Port Contract

Do not admit either the decoded `NewPos=(13824,5120,14848)` or the observed `(28416,2304,21760)` saved/respawn position as a valid `187/187` zone landing.

The next proof must first validate the loaded runtime context and source coordinate frame, then observe real zone membership or `NewCube/NewPos` staging before drawing a transition conclusion.
