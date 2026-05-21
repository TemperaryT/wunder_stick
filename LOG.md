# wunder_stick — Session Log

> Append-only. Most recent entries at top.

---

## 2026-05-21 — Session 3: Phase B (docs + halt-resilience)

**Operator:** Donald Thompson
**Model:** Opus 4.7 (execution)
**Platform:** MSI WSL2

### Actions
- `lib/common.sh`: added `commit_phase()` (idempotent — tags `phase-NN-name-complete`, no-ops on re-run) and `require_python_module()` (precheck with install hint)
- `01_trim_and_sync.sh`: scipy + numpy preflight before audio_sync.py; `commit_phase` at end
- `02_extract_360_crops.sh`: `commit_phase` at end (skipped for `--test-clip` runs)
- `03_extract_frames.sh`: `commit_phase` at end with per-cam counts
- `04_filter_blur.sh`: `commit_phase` at end with per-cam keep counts
- Wrote 6 docs:
  - `docs/00_pipeline_overview.md` — one-pager data flow + phase table + halt-resilience contract
  - `docs/01_capture_field_guide.md` — rig setup, sync clap, lessons from 2026-05-20
  - `docs/02_runbook.md` — copy-paste commands per phase, A/B test recipe
  - `docs/06_lidar_alignment.md` — Reality Scan first, CloudCompare + Open3D ICP fallback
  - `docs/08_postshot_protocol.md` — manual Windows-main procedure, CLI investigation deferred
  - `docs/09_gopro_360_conversion.md` — 5 conversion options + test protocol + decision table

### Decisions
- Phase tags use the form `phase-NN-name-complete` so `git tag | sort` is the restart breadcrumb
- `commit_phase` is no-op on existing tag — re-running a completed phase script doesn't double-commit
- Test-clip GoPro runs skip `commit_phase` (throwaway validation)
- Data dirs (`00_raw/`, `01_edits/`, `02_*/`, frames, `*.ply`, `*.mp4`) remain gitignored; commit_phase only stages tracked metadata (manifests, json, md)

### Phase B complete ✅

---

## 2026-05-21 — Session 2: Opus Plan Review (no code changes)

**Operator:** Donald Thompson
**Model:** Opus 4.7 (review only)
**Platform:** MSI WSL2

### Purpose
Review Sonnet's plan + execution before continuing. Pause point requested for travel.

### Findings vs original plan
- Phase A scripts (01-04) and scaffold ✅ built correctly
- `docs/` was empty (0 of 9 planned docs written) — flagged as blocker
- `scripts/trainers/` was empty — flagged
- Sonnet's `02_extract_360_crops.sh` uses ffmpeg v360=eac:equirect — works but unreliable for GoPro MAX's lens-specific stitching

### Plan revisions (agreed with operator)
1. Postshot demoted from `trainers/` to manual `docs/08_postshot_protocol.md` (paid plan CLI investigation deferred)
2. GoPro Player (Windows) becomes primary equirect path; ffmpeg one of multiple fallbacks to experiment with → `docs/09_gopro_360_conversion.md`
3. Docs written BEFORE scripts 05+; halt-resilience `commit_phase` helper required
4. 2fps vs 5fps becomes explicit A/B test on 30s clip
5. +1.5dB merge target deferred — measure per-cam first; A15 1080p may degrade merged result
6. LiDAR: try Unreal Reality Scan first; CloudCompare/Open3D fallback
7. Execution order revised in plan file

### No file edits to repo this session (except NOW.md + LOG.md)

### Pause point
Working tree clean, plan revised, NOW.md + LOG.md updated for restart resilience.
Next session resumes at Phase B item 1: `commit_phase` helper.

---

## 2026-05-21 — Session 1: Project Bootstrap

**Operator:** Donald Thompson
**Platform:** MSI WSL2

### Actions
- Created full directory structure (00_raw/ → experiments/, scripts/, docs/)
- Moved raw files from project root to proper locations:
  - `00_raw/pixel9/PXL_mid_cam_front_right.mp4` (3.3GB, 4K HEVC 120fps, 7.1min)
  - `00_raw/samsung_a15/A15_lower_cam_rear_right.mp4` (1.2GB, 1080p H.264 ~30fps, 8.1min)
  - `00_raw/gopro_max/GS010513.360` (3.4GB, dual EAC HEVC 50fps, 7.2min)
  - `00_raw/gopro_max/GS010513.LRV` (low-res proxy, 146MB)
  - `00_raw/gopro_max/GS010513.THM` (thumbnail, 115KB)
  - Deleted `PXL_20260520_204616294.mp4:Zone.Identifier` (Windows ADS metadata junk)
- Generated sha256 checksums → `00_raw/checksums.sha256`
- Created `00_raw/camera_manifest.json` with full probe metadata
- Created `CLAUDE.md`, `NOW.md`, `LOG.md`, `.gitignore`

### Key discoveries
- RTX 4090 Laptop GPU (16GB VRAM) accessible in WSL2 via CUDA 13.2 — local training viable
- Pixel 9 shoots at 120fps → aggressive frame decimation needed (target 1-2fps for SfM)
- Samsung A15 is 61s longer than other cameras → audio sync needed to find overlap
- GoPro Max `.360` is dual EAC (two 2272×736 HEVC streams) — needs EAC→equirect via ffmpeg v360 before any frame work
- gsplat 1.4.0 installed in nerfstudio env; 1.5.3 available; `simple_trainer.py` not bundled — needs to be fetched

### Decisions
- Training: LOCAL FIRST (RTX 4090 available). Cloud (Vast.ai) for final runs only.
- gsplat direct as primary trainer (Nerfstudio wrapper retired)
- Postshot (Windows) as blackbox comparison for per-camera baselines
- Audio cross-correlation for sync (all three cameras have 48kHz AAC)
- Master clock: Pixel 9

### Phase 00 complete ✅

---
- 2026-05-21 13:31 phase-01-trim-sync complete. offsets a15=-55.7436s gopro=4.3189s; clip=427.030867s
- 2026-05-21 13:42 phase-03-extract-frames complete. fps=2 width=1920; pixel9=854 a15=854 gopro=2000
- 2026-05-21 13:50 phase-02-gopro-360-crops complete. equirect=854f at 5760x2880; front=854f
