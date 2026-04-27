# Phase 5 0013 Runtime Proof

This note is the canonical summary for the original-runtime `0013` Twinsen-house key, cellar-door, and return slice. The stable machine-readable contract is `tools/fixtures/phase5_0013_runtime_proof.json`; the raw proof bundle is `work/live_proofs/phase5_0013_key_cellar_return_live_20260426_r3`.

## Save And Startup

The run loads the generated original-runtime save by passing `SAVE\scene2-bg1-key-midpoint-facing-key.LBA` as the `LBA2.EXE` argument. Frida observes, MCI-shims, screenshots, and validates memory only; it does not select the save. The loaded save must report `PlayerName=scene2-bg1-key-midpoint-facing-key`, `GamePathname=SAVE\scene2-bg1-key-midpoint-facing-key.LBA`, `NumVersion=0xA4`, and Twinsen at `(3478,2048,4772,beta=3584)` in active cube `0`.

## Gameplay Contract

Pressing `W` from the midpoint spawns one key extra with `SPRITE_CLE`, `Divers=1`, and source `(3072,3072,5120)`. In the validated run it lands near `(3768,2144,4366)`.

Walking Twinsen toward the landed key with heading beta `1428` collects it. The runtime counter changes `NbLittleKeys 0 -> 1`, and the key extra list becomes empty.

After pickup, Twinsen is rotated to face the door with heading beta `2583` and walks forward. The door unlock/open is detected when the key counter changes `NbLittleKeys 1 -> 0` around `(3050,2048,4034)` while still on the Twinsen-house cube.

Continuing forward reaches the cellar transition. The runtime cube changes `active_cube 0 -> 1`, with cellar-side hero position near `(9686,1024,762)` and `NewPos=(9723,1277,762)`. The final cellar screenshot is captured at `(9355,1024,762)`.

Holding `Down` from the cellar side returns through the same doorway. The runtime cube changes `active_cube 1 -> 0`, stages `NewPos=(2562,2049,3686)`, and commits the final house doorway pose `(2562,2048,3686,beta=2583)`.

## Porting Implications

The key is consumed on the house-to-cellar transition, not on the cellar return. The return path is free. This slice is scene `2/background 1 -> scene 2/background 0 -> scene 2/background 1`; do not substitute the older rejected `3/3` Tralu handoffs or the exterior `2/2` public-door seam.

The proof is deliberately tied to runtime-observed fields: `NbLittleKeys`, `active_cube`, `NewPos`, and hero pose. Screenshot-only evidence is insufficient for this slice.
