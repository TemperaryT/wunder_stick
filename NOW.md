# wunder_stick — Now

> Arc-level narrative state. Rewritten as needed. Read this BEFORE acting.

_Last updated: 2026-05-21 — Phase B complete (commit_phase helper + scipy precheck + 6 docs). Next: Phase C validation runs._

## Current arc
**Phase B done.** Halt-resilience helper (`commit_phase`) and `scipy` precheck wired into scripts 01–04. Six docs written (`00_pipeline_overview`, `01_capture_field_guide`, `02_runbook`, `06_lidar_alignment`, `08_postshot_protocol`, `09_gopro_360_conversion`). Next session moves to **Phase C: validation runs** — start with `01_trim_and_sync.sh`, then GoPro 360 test-clip, then 2fps vs 5fps A/B.

## What changed in the plan after Opus review
1. **Postshot demoted** from `scripts/trainers/` to `docs/08_postshot_protocol.md` as a manual comparison tool (paid plan may expose CLI — investigate later, don't pretend it's automation now).
2. **GoPro Player (Windows) is now the primary equirect path.** ffmpeg v360=eac:equirect is one of multiple fallbacks to experiment with. The existing `02_extract_360_crops.sh` uses ffmpeg path — needs validation on a 10s clip before trusting.
3. **Docs come BEFORE more scripts.** Sonnet built scripts 01-04 but skipped all 9 planned docs. Phase B now writes docs first.
4. **`commit_phase` helper required.** Halt-resilience: each phase script ends with a commit + tag so restart is clean.
5. **2fps vs 5fps is now an explicit A/B test** before committing the pipeline (not a guess).
6. **Success target deferred.** Don't pre-set +1.5 dB merged-vs-best — Samsung A15 1080p may degrade merged result. Measure first.
7. **LiDAR alignment:** try Unreal Reality Scan (desktop) first; CloudCompare/Open3D as fallback.

Full revised plan at `/home/ops/.claude/plans/starting-a-new-3dgs-expressive-moon.md`.

## Key context (carry forward)
- RTX 4090 Laptop GPU 16GB VRAM confirmed in WSL2 via CUDA 13.2 — local training viable
- gsplat 1.4.0 installed (nerfstudio env); 1.5.3 available; `simple_trainer.py` NOT bundled — needs fetching
- Pixel 9 4K@120fps, Samsung A15 1080p@30fps, GoPro Max .360 dual EAC @50fps
- All 3 cameras have AAC 48kHz audio — sync via cross-correlation viable
- A15 is 61s longer than Pixel 9; cameras not started simultaneously
- LiDAR (Hovermap) NOT yet uploaded to 00_raw/lidar/

## Phase status
| Phase | Status | Notes |
|---|---|---|
| A scaffold | ✅ 2026-05-21 | folders, CLAUDE/NOW/LOG, scripts 01-04, GitHub repo |
| B docs + safety | ✅ 2026-05-21 | commit_phase + require_python_module helpers; 6 docs written |
| C validation runs | ⏳ **NEXT** | sync test, GoPro 360 experiment, 2fps vs 5fps A/B |
| D remaining scripts | ⏳ | 05-07, gsplat env, 10_train.sh, 11_review |

## Resume instructions (for fresh session — Sonnet or whoever picks up)
1. Read `~/CLAUDE.md` → this project's `CLAUDE.md` → this `NOW.md` → `LOG.md`
2. Read the revised plan at `/home/ops/.claude/plans/starting-a-new-3dgs-expressive-moon.md`
3. Read `docs/02_runbook.md` for the per-phase command reference
4. Phase C item 1 — run `./scripts/01_trim_and_sync.sh`; verify the offsets in `01_edits/sync_offsets.json` look plausible (small, with sign matching capture order) and spot-check with `ffplay` per runbook
5. Phase C item 2 — `./scripts/02_extract_360_crops.sh --test-clip` (10s only); open `02_360_extracted/equirect/frame_000001.jpg`. If seam visible, do the GoPro Player path in `docs/09_gopro_360_conversion.md` before running the full Phase 02
6. Phase C item 3 — 2fps vs 5fps A/B test (commands in `docs/02_runbook.md` Phase 03 section). Pick winner, then run `03_extract_frames.sh --fps <winner>`
7. Then `04_filter_blur.sh`. Phase C done.
8. Commit + push (`commit_phase` calls handle this per-phase automatically), update NOW.md, then Phase D scripts

## Open questions
- GoPro mount position during capture (affects tilted_up crop usefulness)
- LiDAR scan upload ETA
- gsplat 1.4.0 vs 1.5.3 + separate env decision (deferred to Phase D)
- Does paid Postshot expose meaningful CLI? (deferred — check on Windows main)

## Handoff cue
- Working tree clean, all in main on origin
- GitHub: https://github.com/TemperaryT/wunder_stick
- No processed data yet — 01_edits/ through 07_*/ all empty
- Raw files verified by checksums (00_raw/checksums.sha256)
