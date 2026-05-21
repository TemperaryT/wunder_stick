# wunder_stick — Now

> Arc-level narrative state. Rewritten as needed. Read this BEFORE acting.

_Last updated: 2026-05-21 — Phase C complete. Phases 01-04 done. Phase D next (scripts 05-07, training)._

## Current arc
**Phase C done.** All validation runs complete:
- Phase 01: audio sync → A15 offset=-55.74s, GoPro offset=+4.32s, aligned clip=427s
- Phase 02: GoPro EAC→equirect→crops at 2fps (854 equirect + 854 front crops)
- Phase 03: frames extracted at 2fps; pixel9=854, a15=854, gopro=3416 (4 crop views merged)
- Phase 04: blur cull with per-camera thresholds (inline OpenCV, not prep_frames.py)
  - pixel9: 739/854 kept (threshold=5)
  - samsung_a15: 844/854 kept (threshold=5)
  - gopro_max: 3195/3416 kept (threshold=50)
  - Total: 4778 frames across cameras

**Important Phase 04 findings:**
- prep_frames.py has a hidden `--target 100` that silently subsamples + renames files. Do NOT use it for blur-only filtering. Script now uses inline OpenCV Laplacian.
- Laplacian scores are NOT cross-camera comparable: phones score 2-64, GoPro crops score 25-572 (Lanczos ringing inflates GoPro scores). Use per-camera thresholds.
- Total 4778 frames is above the 800-1500 COLMAP target. Phase 05 masking will reduce further; temporal subsampling may be needed before COLMAP.

**Next: Phase D** — write scripts 05-07, set up gsplat, run end-to-end.

## Key calibration data (Phase 04)
| Camera | min | p10 | median | p75 | p90 | max | Used threshold | Kept |
|---|---|---|---|---|---|---|---|---|
| pixel9 | 2.1 | 4.3 | 15.3 | 27.0 | 41.4 | 64.1 | 5 | 739/854 |
| samsung_a15 | 4.7 | 8.2 | 12.9 | 15.4 | 20.9 | 37.4 | 5 | 844/854 |
| gopro_max | 24.6 | 57.1 | 213.6 | 317.3 | 399.1 | 571.7 | 50 | 3195/3416 |

## Key context (carry forward)
- RTX 4090 Laptop GPU 16GB VRAM confirmed in WSL2 via CUDA 13.2 — local training viable
- gsplat 1.4.0 installed (nerfstudio env); 1.5.3 available; `simple_trainer.py` NOT bundled — needs fetching
- Pixel 9 4K@60fps (not 120 — 120 was tbr, not actual fps)
- Samsung A15 1080p@30fps, GoPro Max .360 dual EAC @50fps
- Pixel9 auto-rotation: ffmpeg applies displaymatrix BEFORE vf chain → frames are 1920×3414 portrait. Do NOT add transpose.
- Sequential_matcher (not exhaustive) confirmed for video-derived frames. overlap=15.
- LiDAR (Hovermap) NOT yet uploaded to 00_raw/lidar/
- Equirect-direct COLMAP: modern COLMAP supports OMNIDIRECTIONAL model — perspective crops may not be needed. Decision deferred to Phase 06 script authoring.

## Phase status
| Phase | Status | Notes |
|---|---|---|
| A scaffold | ✅ 2026-05-21 | folders, CLAUDE/NOW/LOG, scripts 01-04, GitHub repo |
| B docs + safety | ✅ 2026-05-21 | commit_phase + require_python_module; 6 docs written |
| C validation runs | ✅ 2026-05-21 | 01-04 complete, per-camera calibration done |
| D remaining scripts | ⏳ **NEXT** | 05-07, gsplat env, 10_train.sh, 11_review |

## Resume instructions (for Phase D)
1. Read `~/CLAUDE.md` → project `CLAUDE.md` → this `NOW.md` → `LOG.md`
2. Check calibration table above before any Phase 04 re-run
3. Phase D item 1 — `scripts/05_mask_moving.sh` (Grounded-SAM-2 via Replicate API; check budget first)
4. Phase D item 2 — `scripts/06_colmap_per_cam.sh` + `lib/colmap_stats.py` (decide: crops or equirect-direct?)
5. Phase D item 3 — `scripts/07_colmap_merge.sh`
6. Phase D item 4 — gsplat env: `find ~/miniforge3 -name simple_trainer.py 2>/dev/null`; decide 1.4.0 vs 1.5.3
7. Phase D item 5 — `scripts/trainers/gsplat_direct.sh` + `scripts/10_train.sh` dispatcher
8. Phase D item 6 — `scripts/11_review_results.sh`
9. End-to-end: per-cam baselines → merged → manual Postshot comparison

## Open questions
- GoPro mount position during capture (affects tilted_up crop usefulness)
- LiDAR scan upload ETA
- gsplat 1.4.0 vs 1.5.3 + separate env decision
- Equirect-direct vs crops for GoPro in COLMAP Phase 06
- Does paid Postshot expose meaningful CLI? (check on Windows main)
- Temporal subsampling before COLMAP? 4778 frames > 1500 target; Phase 05 masking will cut some

## Handoff cue
- Phase C complete — all data through 04_filtered/ is processed
- Scripts 04_filter_blur.sh (inline OpenCV) and 02_extract_360_crops.sh (fps flag) updated this session
- GitHub: https://github.com/TemperaryT/wunder_stick
- Working tree should be clean after commit
