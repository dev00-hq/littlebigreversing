# Source Ownership

Phase 0 uses the classic source tree only as an evidence map. It does not treat these files as transplant targets.

| Bucket | Concrete owner files | Key asset families |
| --- | --- | --- |
| boot and entrypoint | `PERSO.CPP`, `CONFIG/MAIN.CPP` | `BODY.HQR`, `ANIM.HQR`, `SPRITES.HQR`, `RESS.HQR`, `SCREEN.HQR`, `VOX/*.VOX` |
| scene loading | `DISKFUNC.CPP`, `GRILLE.CPP`, `INTEXT.CPP` | `SCENE.HQR`, `LBA_BKG.HQR` |
| exterior loading | `EXTFUNC.CPP`, `3DEXT/LOADISLE.CPP`, `3DEXT/TERRAIN.CPP` | `.ILE/.OBL`, `RESS.HQR` |
| object/runtime loop | `OBJECT.CPP`, `PERSO.CPP` | `BODY.HQR`, `ANIM.HQR`, `SPRITES.HQR`, `RESS.HQR` |
| life scripts | `GERELIFE.CPP`, `COMPORTE.CPP` | `BODY.HQR`, `ANIM.HQR`, `VOX/*.VOX`, `TEXT.HQR` |
| track handling | `GERETRAK.CPP`, `FLOW.CPP` | `RESS.HQR`, `SCENE.HQR` |
| text and voice | `MESSAGE.CPP`, `INVENT.CPP` | `TEXT.HQR`, `VOX/*.VOX`, `SCREEN.HQR` |
| video playback | `PLAYACF.CPP`, `GERELIFE.CPP`, `GERETRAK.CPP` | `VIDEO/VIDEO.HQR`, `RESS.HQR` |
| music and audio | `AMBIANCE.CPP`, `GAMEMENU.CPP` | `RESS.HQR`, `SAMPLES.HQR`, `SCREEN.HQR` |
| save and load | `SAVEGAME.CPP`, `VALIDPOS.CPP` | save payloads plus runtime context rooted in `SCENE.HQR` |
| config and input | `CONFIG.CPP`, `GAMEMENU.CPP`, `PERSO.CPP` | `SCREEN.HQR`, config files |
| shared HQR and resource loading | `COMMON.H`, `MEM.CPP`, `PERSO.CPP` | shared HQR roots and loader state across runtime subsystems |

The generated machine-readable map in `work/phase0/source_ownership.json` must keep concrete owner paths, line evidence, entrypoints, and asset-family references for every bucket above.
