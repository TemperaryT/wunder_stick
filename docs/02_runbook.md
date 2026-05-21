# wunder_stick — Runbook

Copy-paste commands per phase. Keep in sync with `scripts/`. Always run from
the project root: `cd ~/projects/wunder_stick`.

## Conventions

- All scripts source `scripts/lib/common.sh` and use `set -euo pipefail`.
- Scripts end with `commit_phase` — interrupting before that line means the phase
  did NOT record. Re-run is safe (commit_phase no-ops on existing tag).
- `--test-clip` and `--cam <name>` flags exist where indicated; use them before
  full-pipeline runs to validate.
- `nvidia-smi` before any training to confirm RTX 4090 visible from WSL2.

## Environments

| Env | Used for | Activate |
|---|---|---|
| `fselect` | Phases 01, 04, 06 (COLMAP 3.13 + GLOMAP + scipy + ffmpeg) | `conda activate fselect` |
| `nerfstudio` | Training (gsplat 1.4.0) | `conda activate nerfstudio` |

Scripts call `activate_env` from `common.sh` themselves — don't pre-activate.

---

## Phase 00 — Raw ingest (DONE)

Already complete. To re-verify integrity:

```bash
sha256sum -c 00_raw/checksums.sha256
```

If anything fails: STOP. Do not re-process. Investigate which file diverged and
restore from original capture media before proceeding.

---

## Phase 01 — Trim + audio sync

```bash
./scripts/01_trim_and_sync.sh
# inspect:
cat 01_edits/sync_offsets.json
ffprobe -v error -show_entries format=duration -of csv=p=0 01_edits/pixel9_trimmed.mp4
```

Spot-check sync visually:

```bash
ffplay 01_edits/pixel9_trimmed.mp4 &
ffplay 01_edits/samsung_a15_trimmed.mp4 &
# verify same event at same wall-clock timestamp
```

Re-run with manual override if auto-detect end time is wrong:

```bash
./scripts/01_trim_and_sync.sh --end-time 420 --skip-sync
```

---

## Phase 02 — GoPro 360 → equirect → crops

**FIRST RUN (validation):**

```bash
./scripts/02_extract_360_crops.sh --test-clip
# inspect first frame of equirect — looks like a continuous panorama? seam visible?
ls -la 02_360_extracted/equirect/ | head
xdg-open 02_360_extracted/equirect/frame_000001.jpg  # or scp to Windows main
```

If equirect is broken (visible seam, mirrored half), STOP and run the GoPro Player
fallback documented in `09_gopro_360_conversion.md`. Then re-import the equirect
MP4 and skip the ffmpeg EAC→equirect step.

**FULL RUN:**

```bash
./scripts/02_extract_360_crops.sh
```

---

## Phase 03 — Frame extraction

**A/B TEST FIRST (per plan):**

```bash
# Test 2fps on a 30s test clip
ffmpeg -y -ss 60 -t 30 -i 01_edits/pixel9_trimmed.mp4 -c copy /tmp/px9_test.mp4
ffmpeg -y -i /tmp/px9_test.mp4 -vf "fps=2,scale=1920:-2:flags=lanczos" -q:v 2 /tmp/abtest_2fps/px9_%06d.jpg
ffmpeg -y -i /tmp/px9_test.mp4 -vf "fps=5,scale=1920:-2:flags=lanczos" -q:v 2 /tmp/abtest_5fps/px9_%06d.jpg
# run quick COLMAP on each (see 06 below), compare registration % + reproj err
```

Then set winning fps:

```bash
./scripts/03_extract_frames.sh --fps 2
# or
./scripts/03_extract_frames.sh --fps 5
```

---

## Phase 04 — Blur cull

```bash
./scripts/04_filter_blur.sh
# or one camera at a time:
./scripts/04_filter_blur.sh --cam pixel9 --threshold 40
```

If a camera reports `<50% kept` or `>95% kept` warnings, adjust threshold:
- low keep → threshold too strict, try 30
- high keep → threshold too permissive, try 60

---

## Phase 05 — Moving-object masking (TBD)

Script not yet written. Planned interface:

```bash
./scripts/05_mask_moving.sh --provider replicate --prompt "person, worker, forklift"
# or zero-cost fallback:
./scripts/05_mask_moving.sh --provider mog2
```

---

## Phase 06 — Per-cam COLMAP (TBD)

Script not yet written. Planned interface:

```bash
./scripts/06_colmap_per_cam.sh --cam pixel9
# inspect:
cat 06_colmap_per_cam/pixel9/stats.json
```

Quality gate (auto-enforced by script, will exit non-zero if not met):
- registered_images / total_images >= 0.85
- num_points3D >= 10000
- mean_reproj_error < 1.5px

---

## Phase 07 — Multi-cam merge (TBD)

Script not yet written. Strategy A (preferred) re-runs COLMAP on the union frame set:

```bash
./scripts/07_colmap_merge.sh --strategy A
```

---

## Phase 09 — Training

`10_train.sh` dispatches to a trainer backend. Not yet wired up.

```bash
# gsplat direct (local RTX 4090)
./scripts/10_train.sh --trainer gsplat --scene-dir 07_colmap_merged --exp-id 001
# review:
./scripts/11_review_results.sh --exp-id 001
```

For Postshot (manual, Windows main), see `08_postshot_protocol.md`.

---

## Phase 08 — LiDAR registration (deferred)

See `06_lidar_alignment.md`. Will run after Hovermap scan is uploaded to `00_raw/lidar/`.

---

## Resume after halt

```bash
git tag | sort                              # which phases are committed?
cat NOW.md                                  # arc state
tail -30 LOG.md                             # recent decisions
# then pick up at the next ⏳ phase in 00_pipeline_overview.md
```

To force re-run a completed phase, delete its tag first:

```bash
git tag -d phase-03-extract-frames-complete
```
