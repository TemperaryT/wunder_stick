# wunder_stick — Pipeline Overview

One-pager. Read this first; deeper docs are per-phase.

## Data flow

```
00_raw/        (immutable originals + checksums)
   │
   ▼   01_trim_and_sync.sh        audio xcorr → sync_offsets.json + lossless trim
01_edits/      pixel9_trimmed.mp4, samsung_a15_trimmed.mp4, gopro_max_trimmed.360
   │
   ▼   02_extract_360_crops.sh    .360 EAC → equirect → 4 perspective crops
02_360_extracted/                  front/ right/ left/ tilted_up/
   │
   ▼   03_extract_frames.sh       ffmpeg fps decimation (phones); copy crops (GoPro)
03_frames/     pixel9/  samsung_a15/  gopro_max/
   │
   ▼   04_filter_blur.sh          prep_frames.py --threshold 40
04_filtered/   pixel9/  samsung_a15/  gopro_max/  _rejected/
   │
   ▼   05_mask_moving.sh          Grounded-SAM-2 (Replicate) or MOG2
05_masked/     pixel9/  samsung_a15/  gopro_max/  masks/
   │
   ▼   06_colmap_per_cam.sh       COLMAP 3.13 + GLOMAP, per camera (quality gate)
06_colmap_per_cam/<cam>/sparse/0/  + stats.json
   │
   ▼   07_colmap_merge.sh         Strategy A: union re-run / Strategy B: model_merger
07_colmap_merged/sparse/0/
   │
   ▼   10_train.sh --trainer gsplat|lichtfeld   (Postshot manual on Windows)
experiments/exp-NNN-<desc>/        splat.ply + README + metrics
   │
   ▼   11_review_results.sh       append to results/metrics_summary.csv
results/       winning_splat.ply (symlink) + metrics_summary.csv

08_lidar/      (deferred — Hovermap E57 alignment, see docs/06_lidar_alignment.md)
```

## Phase status table

| # | Phase | Script | Status | Critical notes |
|---|---|---|---|---|
| 00 | Raw ingest | `00_ingest_raw.sh` | ✅ done | `00_raw/` immutable after this |
| 01 | Trim + audio sync | `01_trim_and_sync.sh` | ⏳ next | Pixel 9 is master clock |
| 02 | GoPro 360 → crops | `02_extract_360_crops.sh` | ⏳ | ffmpeg path needs validation vs GoPro Player; see `09_gopro_360_conversion.md` |
| 03 | Frame extraction | `03_extract_frames.sh` | ⏳ | 2fps vs 5fps A/B before committing pipeline |
| 04 | Blur cull | `04_filter_blur.sh` | ⏳ | output in SIBLING dir, never under 03_frames |
| 05 | Moving-object masking | `05_mask_moving.sh` | ⏳ | Grounded-SAM-2 Replicate; MOG2 fallback |
| 06 | Per-cam COLMAP | `06_colmap_per_cam.sh` | ⏳ | GoPro needs `MIXED_CAMERAS=1`; ≥85% registered gate |
| 07 | Multi-cam merge | `07_colmap_merge.sh` | ⏳ | A: union re-run preferred; B: model_merger fallback |
| 08 | LiDAR alignment | `08_lidar_register.sh` | ⏸ deferred | scan not yet uploaded |
| 09 | Training | `10_train.sh` | ⏳ | gsplat direct primary; Postshot manual reference |
| 10 | Results review | `11_review_results.sh` | ⏳ | confirm SH-coeff PLY (not RGB) |

## Halt resilience contract

Each phase script ends with `commit_phase "phase-NN-name" "notes"` which:

- Appends a line to `LOG.md`
- Stages `NOW.md`, `LOG.md`, and the relevant manifests/json artifacts
- Commits with message `phase: phase-NN-name — notes`
- Tags `phase-NN-name-complete`
- **Idempotent:** if the tag already exists, the call is a no-op

This means a fresh session can `git tag | sort` to see exactly where the pipeline got
before the prior session was halted, and re-running a completed phase script will
re-do the work but harmlessly skip the second commit.

## Non-negotiable rules (inherited from automation_server)

- `filter_frames → COLMAP → train` — always in order
- Filtered frames in **sibling** dirs, never under the COLMAP image path
- GoPro 360 crops in COLMAP **require** `MIXED_CAMERAS=1`
- PLY export **must** use SH coefficients (`f_dc_*`, `f_rest_*`), not RGB
- COLMAP pinned to **3.13.0** (4.x breaks GLOMAP)
- Every `find ... | wc -l` needs `|| VAR=0` fallback

## See also

- `02_runbook.md` — copy-paste commands per phase
- `01_capture_field_guide.md` — how to capture future scenes for this pipeline
- `09_gopro_360_conversion.md` — GoPro Max .360 conversion options
- `08_postshot_protocol.md` — manual Postshot comparison procedure
- `06_lidar_alignment.md` — LiDAR registration plan (deferred)
- `lessons_learned.md` — project-specific gotchas as we hit them
- `/home/ops/projects/wunder_stick/CLAUDE.md` — project charter + startup contract
