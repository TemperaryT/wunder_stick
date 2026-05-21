# wunder_stick — Now

> Arc-level narrative state. Rewritten as needed. Read this BEFORE acting.

_Last updated: 2026-05-21 — Phase 00 complete, Phase 01 queued_

## Current arc
**Setup phase.** Folder structure created, raw videos ingested and checksummed, project
docs initialized. Ready to begin video editing and sync.

**Key discovery:** RTX 4090 Laptop GPU (16GB VRAM) is fully accessible in WSL2 via CUDA.
Most experiments will run locally. Cloud (Vast.ai) reserved for final high-quality runs only.

**Training path:** gsplat 1.4.0 installed in `nerfstudio` conda env. `simple_trainer.py`
(gsplat's reference trainer) not yet fetched — needed before Phase 09. gsplat 1.5.3 is
available on PyPI. Upgrade + separate env to be created before first training run.

## Camera sync situation
Samsung A15 is 61s longer than Pixel 9 (488s vs 427s). Cameras were not started
simultaneously. Audio cross-correlation needed to find the overlap region before
trimming. Master clock = Pixel 9.

## GoPro Max format note
File is .360 (GoPro proprietary EAC dual-fisheye, two 2272×736 HEVC streams).
Must convert to equirectangular before any frame extraction. ffmpeg v360 available
and tested. Conversion command to validate on a short clip before committing.

## Open questions
- **GoPro mount position during capture?** Body strap vs pole — affects which crops
  are useful (tilted_up may be irrelevant if camera was stationary at head height)
- **LiDAR scan upload ETA?** Scan not yet in 00_raw/lidar/. Phase 08 blocked until it arrives.
- **gsplat upgrade:** Stay on 1.4.0 or move to 1.5.3 + new conda env? Leaning toward
  new env to keep nerfstudio env stable.

## Phase status
| Phase | Status | Notes |
|---|---|---|
| 00 raw ingest | ✅ 2026-05-21 | 3 cameras, checksums written |
| 01 trim+sync | ⏳ next | audio cross-correlation pending |
| 02 GoPro equirect | ⏳ | after 01 |
| 03 frame extract | ⏳ | |
| 04 blur cull | ⏳ | |
| 05 masking | ⏳ | |
| 06 per-cam COLMAP | ⏳ | |
| 07 merged COLMAP | ⏳ | |
| 08 LiDAR | ⏸ | scan not uploaded yet |
| 09 training | ⏳ | gsplat env setup needed first |
| 10 review | ⏳ | |

## Immediate next actions
1. Write `scripts/lib/audio_sync.py` for audio cross-correlation
2. Write `scripts/01_trim_and_sync.sh`
3. Run sync to identify overlap region → produce trimmed videos in `01_edits/`
4. Test GoPro EAC → equirect conversion on a 10s clip
5. Write `scripts/02_extract_360_crops.sh`
6. Create gsplat training env + fetch `simple_trainer.py`

## Handoff cue
- Phase 00 complete. Raw files in 00_raw/, checksums in 00_raw/checksums.sha256
- Not yet a git repo — no commits yet
- No cloud spend
- No processed frames yet
- Start by reading: CLAUDE.md → NOW.md → 00_raw/camera_manifest.json
