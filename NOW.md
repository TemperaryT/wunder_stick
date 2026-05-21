# wunder_stick — Now

> Arc-level narrative state. Rewritten as needed. Read this BEFORE acting.

_Last updated: 2026-05-21 — Phase A complete (scaffold + sonnet-built scripts 01-04). Plan revised after Opus review. Paused for travel._

## Current arc
**Paused at a safe spot.** Phase A (scaffold) is committed and pushed. Plan was reviewed by Opus and revised — execution order changed. Next session should resume with **Phase B (docs + safety) BEFORE writing any more scripts**.

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
| B docs + safety | ⏳ **NEXT** | commit_phase helper, scipy check, all 9 docs |
| C validation runs | ⏳ | sync test, GoPro 360 experiment, 2fps vs 5fps A/B |
| D remaining scripts | ⏳ | 05-07, gsplat env, 10_train.sh, 11_review |

## Resume instructions (for fresh session — Sonnet or whoever picks up)
1. Read `~/CLAUDE.md` → this project's `CLAUDE.md` → this `NOW.md` → `LOG.md`
2. Read the revised plan at `/home/ops/.claude/plans/starting-a-new-3dgs-expressive-moon.md`
3. Begin Phase B item 1: add `commit_phase` helper to `scripts/lib/common.sh`
4. Retrofit existing scripts 01-04 to call `commit_phase` on success
5. Add `python3 -c "import scipy"` precheck to `01_trim_and_sync.sh`
6. Write the 9 docs (see plan's Phase B list, items 3-8)
7. Commit + push, update NOW.md, then move to Phase C validation runs

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
