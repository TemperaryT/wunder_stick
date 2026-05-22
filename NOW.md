# wunder_stick — Now

> Arc-level narrative state. Rewritten as needed. Read this BEFORE acting.

_Last updated: 2026-05-22 01:33 — GoPro re-processing running overnight. Strategy shift in progress._

## No active processes. Safe to move/restart machine.

## Current arc
**SUSPENDED — new footage collection planned.**
All work on the 2026-05-20 capture is paused. Root cause: footage walks through 2-3 distinct
rooms in one continuous clip — COLMAP cannot build a coherent single model from mixed-scene footage.
Decision: collect simpler new footage with good overlap first, build pipeline confidence, then
return to the complex multi-room footage (edited into per-room clips via DaVinci Resolve).

### Phase 06 — Pixel9 COLMAP result (completed 2026-05-22)
vocab_tree_matcher (nn=30) registered **39.1%** (289/739 frames). Gate failed (need 85%).
Diagnosis: 62k matched pairs but 97% failed RANSAC — scene repetition signature.
**Decision: Pixel9 footage may not be suitable.** Camera had close-ups, turns, erratic movement.
User is evaluating via Postshot (suspended for now). May drop Pixel9 from pipeline.

### Per-cam COLMAP final results (2026-05-22)
| Camera | Registered | Points3D | Reproj | Notes |
|---|---|---|---|---|
| Pixel9 | 289/739 (39.1%) | 29,712 | 2.05px | Failed — erratic footage, multi-room |
| Samsung A15 | 58/844 (6.9%) | 5,178 | 1.55px | Failed — same root cause |
| GoPro Max | 2600/3244 (80.1%) | 247,759 | 1.04px | Best result — 4-dir rig helps |

**Root cause of failures:** All three cameras walked through 2-3 distinct rooms in one clip.
COLMAP cannot build one model from geometrically disconnected spaces. Vocab_tree finds
visual matches between similar industrial elements in different rooms; RANSAC rejects them.
**Fix:** Edit footage to per-room clips before processing.

### GoPro re-processing (completed 2026-05-22)
- Root cause of bad GoPro data: `02_extract_360_crops.sh` used `v360=eac:equirect` (wrong format)
  GoPro Max .360 is dual fisheye, not EAC. Output was garbage — "slices of equirectangular".
- Fix: GoPro Player (Windows) exported proper equirectangular → `gopro_equa.mp4` (3072×1536)
- Old bad data: all cleared (02_360_extracted/, 03_frames/gopro_max/, 04_filtered/gopro_max/, 05_masked/gopro_max/, 05_masked/masks/gopro_max/)
- New pipeline running: trim (gopro offset=+4.32s) → 4 perspective crops (front/right/left/rear, pitch=0, no tilted_up)
- Skip tilted_up: user confirmed overhead lights are harsh; pitch=0 crops avoid nadir (operator) and zenith (lights)

### Next steps when resuming
**Path A — new simple footage (immediate):**
1. Capture single-scene footage with good overlap (see capture guidelines in docs/01_capture_field_guide.md)
2. Run pipeline from Phase 01 — all scripts proven and ready

**Path B — return to this footage (later, via DaVinci edits):**
1. Edit each video to per-room clips in DaVinci Resolve
2. Re-sync the trimmed clips (audio cross-correlation still works)
3. Re-run from Phase 03 (frame extraction) — masking/COLMAP config already known
4. GoPro: 80.1% with full clip → likely better with single-room clip

**GoPro escalation (if COLMAP still fails after editing):**
1. Lichtfeld 360° plugin on `gopro_equa_trimmed.mp4`
2. Metashape native spherical SfM (Standard ~$179)

## Key calibration data (Phase 04)
| Camera | min | p10 | median | p90 | max | Threshold | Kept |
|---|---|---|---|---|---|---|---|
| pixel9 | 2.1 | 4.3 | 15.3 | 41.4 | 64.1 | 5 | 739/854 |
| samsung_a15 | 4.7 | 8.2 | 12.9 | 20.9 | 37.4 | 5 | 844/854 |
| gopro_max (GoPro Player) | 90.2 | 186.9 | 323.8 | 444.1 | 549.2 | 150 | 3244/3416 |

## Phase status
| Phase | Status | Notes |
|---|---|---|
| 00 raw ingest | ✅ | checksums verified |
| 01 trim+sync | ✅ | a15=-55.74s, gopro=+4.32s, clip=427s |
| 02 GoPro 360 | ✅ | GoPro Player equirect → 4 crops (front/right/left/rear, pitch=0, 1920×1440) |
| 03 frames | ✅ | px9=739, a15=844, gp=3416 (4 dirs) |
| 04 blur cull | ✅ | px9=739, a15=844, gp=3244 (threshold=150, min score=90) |
| 05 masking | ✅ | px9/a15=passthrough, gp=passthrough (pitch=0 crops exclude nadir/zenith) |
| 06 COLMAP per-cam | ⚠️ | pixel9=39.1% (below gate, may drop). a15+gopro pending |
| 07 COLMAP merge | ⏳ | |
| 08 LiDAR | ⏸ | deferred — scan not yet uploaded |
| 09/10 training | ⏳ | gsplat simple_trainer.py at ~/.cache/gsplat_examples/ |
| 11 review | ⏳ | |

## Key technical facts (carry forward)
- COLMAP 3.13.0 + GLOMAP confirmed in `fselect` env
- GPU flags: `--FeatureExtraction.use_gpu 1`, `--FeatureMatching.use_gpu 1` (NOT SiftExtraction/SiftMatching)
- Vocab tree: pre-built, at `~/.cache/colmap_vocab/vocab_tree_flickr100K_words256K.bin` (70MB)
- vocab_tree_builder is unusably slow on CPU — NEVER use it
- sequential_matcher fails for fast-moving cameras — always use vocab_tree_matcher
- gsplat 1.4.0 in `nerfstudio` env; simple_trainer.py at `~/.cache/gsplat_examples/simple_trainer.py`
- gsplat CLI: `python3 simple_trainer.py mcmc --data_dir <dir> --result_dir <dir> --strategy.cap_max 1000000 --max_steps 30000 --antialiased`
- Pixel9 frames are 1920×3414 portrait (displaymatrix auto-rotate applied by ffmpeg)
- Phase 06 creates `images/` symlink in each colmap dir → ready for gsplat `--data_dir`

## Inspection commands
```bash
# Is COLMAP still running?
ps aux | grep "colmap\|glomap" | grep -v grep

# Phase 06 results (after each cam completes):
cat 06_colmap_per_cam/pixel9/stats.json
cat 06_colmap_per_cam/samsung_a15/stats.json
cat 06_colmap_per_cam/gopro_max/stats.json

# Run remaining cameras (after pixel9 done):
bash scripts/06_colmap_per_cam.sh --cam samsung_a15
bash scripts/06_colmap_per_cam.sh --cam gopro_max

# Phase 07 merge:
bash scripts/07_colmap_merge.sh

# Training:
bash scripts/10_train.sh --trainer gsplat \
    --scene-dir 07_colmap_merged \
    --desc merged-v1
```

## Handoff cue
- GitHub: https://github.com/TemperaryT/wunder_stick (all commits pushed)
- Working tree: clean (or minor LOG.md staged from commit_phase)
- Active process: colmap vocab_tree_matcher on Pixel9 — check before doing anything
