# wunder_stick — Project Context

> Assumes ~/CLAUDE.md has been loaded. If not, read it first.

## Startup Contract
1. Read this CLAUDE.md
2. Read NOW.md — current arc state
3. Skim docs/00_pipeline_overview.md when available
4. Load only when relevant:
   - automation_server/docs/3dgs_lessons_learned.md (non-negotiable rules)
   - docs/02_runbook.md (command reference)
   - docs/lessons_learned.md (project-specific gotchas)
5. Brief operator: current phase, last action, next action
6. Wait for operator confirmation before acting

## Goal
Build a repeatable, documented multi-camera 3DGS capture pipeline for industrial scenes.
The PROCESS is the deliverable; this particular splat is the validation run.

Done means: (1) all 3 cameras produce valid per-cam COLMAP models, (2) merged splat
exceeds best per-camera splat by ≥1.5 dB PSNR, (3) docs/ is complete enough that
a fresh operator can re-run on a new scene without consulting anyone.

## Hardware — This Capture (2026-05-20)
| Camera | Position | File | Resolution | FPS | Duration |
|---|---|---|---|---|---|
| Pixel 9 | mid, front-right | PXL_mid_cam_front_right.mp4 | 4K | 120fps | 7.1min |
| Samsung A15 | lower, rear-right | A15_lower_cam_rear_right.mp4 | 1080p | ~30fps | 8.1min |
| GoPro Max | 360° | GS010513.360 (dual EAC) | 2272x736×2 | 50fps | 7.2min |

LiDAR: Emerson Hovermap scan — not yet uploaded. Will go to 00_raw/lidar/ when ready.

## Training Approach — LOCAL FIRST
Most experiments run locally. Cloud (Vast.ai) reserved for final high-quality runs or
when local GPU is insufficient.

Local GPU path: Linux dual-boot (full GPU access) or WSL2 CUDA passthrough if configured.
Check `nvidia-smi` before assuming GPU availability in WSL.

Trainers (in order of preference for local work):
1. **gsplat direct** — `scripts/trainers/gsplat_direct.sh` — primary research tool
2. **Postshot** — Windows, GUI, fast blackbox comparison for per-cam baselines
3. **Lichtfeld** — Docker, for specific comparison points

## Phase Status
| Phase | Description | Status |
|---|---|---|
| 00 | Raw video ingest + checksum | ✅ complete (2026-05-21) |
| 01 | Trim + audio sync | ⏳ next — need to identify overlap region |
| 02 | GoPro 360 EAC → equirect → crops | ⏳ |
| 03 | Frame extraction | ⏳ |
| 04 | Blur cull | ⏳ |
| 05 | Moving-object masking | ⏳ |
| 06 | Per-cam COLMAP | ⏳ |
| 07 | Multi-cam COLMAP merge | ⏳ |
| 08 | LiDAR alignment | ⏸ deferred — scan not yet uploaded |
| 09 | Training (gsplat direct) | ⏳ — investigate version/flags first |
| 10 | Results review | ⏳ |

## Infrastructure Reused
- `~/projects/automation_server/scripts/prep_frames.py` — frame extract + blur cull
- conda env `fselect` — COLMAP 3.13.0 + GLOMAP 1.2.0 + faiss + ffmpeg (PINNED)
- conda env `nerfstudio` — gsplat installed here; Nerfstudio wrapper NOT used

## Critical Non-Negotiables
From automation_server/docs/3dgs_lessons_learned.md:
- filter_frames → COLMAP → train. Never out of order.
- Filtered frames in SIBLING dirs (04_filtered/), never under COLMAP image path.
- GoPro 360 crops REQUIRE MIXED_CAMERAS=1 in COLMAP.
- PLY export: SH coefficients (f_dc_*, f_rest_*), NOT RGB.
- COLMAP pin: 3.13.0 (not 4.x — breaks glomap).
- Every `find ... | wc -l` needs `|| VAR=0` fallback.

## Key Numbers (this capture)
- Pixel 9 at 2fps: ~854 frames
- Samsung A15 at 2fps: ~976 frames  
- GoPro Max at 2fps: ~863 frames (×3 crops = ~2589 frame images)
- Target total after filtering: 800–1500 frames across all cameras

## Directory Boundaries
- Build: this repo (scripts, docs, manifests — tracked in git)
- Data: 00_raw/ → 07_colmap_merged/ (large binaries — gitignored)
- Experiments: experiments/ (READMEs tracked; PLY files gitignored)

## Standing Rules
- 00_raw/ is immutable after ingest. Verify checksums before any re-process.
- One experiment = one dir in experiments/, one row in results/metrics_summary.csv.
- Update NOW.md before session-end commit.
- Append LOG.md after every discrete decision or completed phase.
- Update docs/lessons_learned.md immediately on any non-obvious gotcha.

## References
- NOW.md, LOG.md
- 00_raw/camera_manifest.json — capture metadata
- automation_server/docs/3dgs_lessons_learned.md — inherited lessons
