# wunder_stick — Now

> Arc-level narrative state. Rewritten as needed. Read this BEFORE acting.

_Last updated: 2026-05-22 — Phase D execution in progress. COLMAP Pixel9 running._

## CRITICAL — Active process (do NOT kill)
PID 193817: `colmap vocab_tree_matcher` on Pixel9 database.
Running since ~00:27 on 2026-05-22. Check with:
```bash
ps aux | grep "colmap\|glomap" | grep -v grep
```
The script `06_colmap_per_cam.sh --cam pixel9` is running in the background.
After vocab_tree_matcher finishes, it will automatically run GLOMAP and produce stats.json.

## Current arc
**Phase D execution in progress.** Phases 01–05 complete. Phase 06 (COLMAP per-cam) underway.

### Phase 06 — what happened so far
1. First attempt (sequential_matcher, overlap=30): 49/739 frames (6.6%) — failed.
   Root cause: camera moving too fast for sequential matching. Even adjacent frames shared
   too few SIFT features (6367 of expected 21k+ pairs had ANY match).
2. vocab_tree_builder attempt: killed after 12+ hours — CPU faiss k-means never finishes.
3. Current attempt: vocab_tree_matcher with pre-built COLMAP Flickr100K 256K-word tree
   (downloaded to ~/.cache/colmap_vocab/vocab_tree_flickr100K_words256K.bin, 70MB).
   This is the correct approach and should complete in minutes.

### Next steps after Pixel9 COLMAP completes
1. Check `06_colmap_per_cam/pixel9/stats.json` — need registered_pct >= 85%
2. If registration still low (<50%): see troubleshooting below
3. Run A15: `bash scripts/06_colmap_per_cam.sh --cam samsung_a15`
4. Run GoPro: `bash scripts/06_colmap_per_cam.sh --cam gopro_max`
5. Phase 07: `bash scripts/07_colmap_merge.sh`
6. Phase 10: `bash scripts/10_train.sh --trainer gsplat --scene-dir 07_colmap_merged`

### If Pixel9 registration is still low after vocab_tree run
Try in order:
- Increase nn: `--nn 50` (matches each frame to 50 nearest instead of 30)
- Check if scene is too repetitive (industrial scenes with repetitive walls are hard)
- Lower blur threshold further (many blurry frames = bad matching)
- Consider extracting at higher fps (3fps instead of 2fps) for more frame overlap

## Key calibration data (Phase 04)
| Camera | min | p10 | median | p90 | max | Threshold | Kept |
|---|---|---|---|---|---|---|---|
| pixel9 | 2.1 | 4.3 | 15.3 | 41.4 | 64.1 | 5 | 739/854 |
| samsung_a15 | 4.7 | 8.2 | 12.9 | 20.9 | 37.4 | 5 | 844/854 |
| gopro_max | 24.6 | 57.1 | 213.6 | 399.1 | 571.7 | 50 | 3195/3416 |

## Phase status
| Phase | Status | Notes |
|---|---|---|
| 00 raw ingest | ✅ | checksums verified |
| 01 trim+sync | ✅ | a15=-55.74s, gopro=+4.32s, clip=427s |
| 02 GoPro 360 | ✅ | equirect=854f at 5760x2880; 4 crops |
| 03 frames | ✅ | px9=854, a15=854, gp=3416 |
| 04 blur cull | ✅ | inline OpenCV; px9=739, a15=844, gp=3195 |
| 05 masking | ✅ | phones=passthrough, gopro=MOG2 |
| 06 COLMAP per-cam | 🔄 | pixel9 running; a15+gopro pending |
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
