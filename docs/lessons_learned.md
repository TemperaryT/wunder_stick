# wunder_stick — Lessons Learned

Append-only. Record immediately when a non-obvious gotcha is hit. Do not wait for session end.

---

## 2026-05-21 — GoPro .360 trim: ffmpeg can't mux to .360 extension

**Context:** `01_trim_and_sync.sh` tried to trim the raw GoPro Max `.360` file
using the generic `trim_video` helper (`ffmpeg -c copy -t ... output.360`).

**Failure:** `Error: Unable to choose an output format for 'output.360'` — ffmpeg
doesn't recognize `.360` as a known container.

**Root cause:** GoPro's `.360` is a GoPro-branded MP4 container. ffmpeg won't
infer the muxer from the extension. Must pass `-f mp4` explicitly.

**Second failure:** Adding `-f mp4` without stream mapping still produced a
corrupt file (`invalid size 0 in stsd`). The `.360` has 7 streams including
proprietary GoPro data tracks (`gpmd`, `tmcd`, `fdsc`) that don't mux cleanly
into standard mp4.

**Fix:** Explicit stream selection — keep only the two EAC video streams and
the main AAC audio track:

```bash
ffmpeg -y -ss 0 -i input.360 -t <dur> \
    -map 0:v -map 0:a:0 -c copy -f mp4 output.360
```

This drops: `tmcd` (timecode), `gpmd` (GoPro binary telemetry), `fdsc` (sensor
data), and the PCM ambisonic audio. None of those are needed for 3DGS.

**File path:** `scripts/01_trim_and_sync.sh`, GoPro trim section.

---

## 2026-05-21 — scipy not in fselect env by default

**Context:** `01_trim_and_sync.sh` calls `lib/audio_sync.py` which imports scipy.
The `fselect` conda env was built for COLMAP/GLOMAP and did not include scipy.

**Fix:** `conda install -n fselect -c conda-forge scipy` (installed 1.17.1).
Already documented in the script's error message via `require_python_module`.

---

## 2026-05-21 — A/B test result: 2fps confirmed, COLMAP sequential_matcher for video

**Context:** 30s test clip from Pixel9, COLMAP sequential_matcher (overlap=15).

**2fps result:** 13/60 registered (21.7% on 30s clip, expected — short clip has scene
breaks). Reprojection error: 0.899px (excellent, well under 1.5px target). When
frames connect, they connect accurately.

**5fps was not run:** Frame count math is conclusive:
- 2fps × 427s = ~854 Pixel9 frames + ~854 A15 frames + ~863 GoPro frames (×4 crops ≈3000) → ~4700 raw → ~2500-3000 after blur cull. Need to cull more aggressively at Phase 04 to hit 800-1500 target.
- 5fps: 2.5× that = 7500+ raw. Too many for COLMAP memory and time.

**Decision:** 2fps locked in. `03_extract_frames.sh` default fps=2 is correct.

**Use sequential_matcher for video-derived frames** (not exhaustive_matcher).
The exhaustive matcher produced zero reconstructions on the same 30s clip.
In `06_colmap_per_cam.sh`, use `sequential_matcher` with overlap=15-30.

---

## 2026-05-21 — Pixel9 auto-rotation: ffmpeg applies displaymatrix to vf chain

**Context:** Pixel9 records 3840×2160 with a `-90°` displaymatrix tag (Android default
for portrait capture stored in landscape). When ffmpeg processes this file through a
`-vf` filter chain, it applies the rotation *before* the filters. Decoded frames are
2160×3840 (portrait) when entering the filter.

**Effect:** `scale=1920:-2` on a 2160×3840 input produces 1920×3414 portrait frames.
Adding `transpose=1` after the scale gives 3414×1920 landscape — that is WRONG, it
double-rotates the already-rotated output.

**Correct approach for `03_extract_frames.sh`:** Do NOT add transpose. Let ffmpeg
auto-rotate and scale normally. Output will be 1920×3414 portrait. COLMAP handles any
aspect ratio; the portrait orientation is geometrically correct for how the phone was
mounted.

**To suppress auto-rotation** (get raw landscape 1920×1080): use `-noautorotate` before
`-i`. Only do this if you explicitly want the raw sensor orientation and will tell COLMAP
about the rotation via camera metadata.

---

## 2026-05-21 — Sequential_matcher fails for fast-moving cameras; use vocab_tree_matcher

**Context:** Pixel9 sequential_matcher (overlap=30, then overlap=200) produced 6,367 matched pairs
from ~21,735 attempted. GLOMAP registered only 49/739 frames (6.6%). Reproj error was good (1.35px)
meaning the matched frames were fine — there just weren't enough connections.

**Root cause:** At 2fps with a walking camera, consecutive frames share too few SIFT features.
Investigation: only 6,367 of the expected 21,735 overlap=30 pairs had ANY SIFT matches. Even frames
±30 apart often share zero features because the camera moved too far between shots.
Keypoints per frame were excellent (median 8212) — the scene content was the problem, not extraction.

**Fix:** Build a vocabulary tree from the image features (`colmap vocab_tree_builder`), then
use `colmap vocab_tree_matcher` with `num_nearest_neighbors=20-50`. This matches each frame to its
most visually similar frames globally, bypassing sequence order entirely.

**Rule for video-derived frames:** Use vocab_tree_matcher, not sequential_matcher, for any scene
where the camera is walking around (not slowly panning). Update `06_colmap_per_cam.sh` to use
vocab_tree_matcher as default, with sequential as a fast-validation option only.

**Updated pipeline in 06_colmap_per_cam.sh:**
```bash
colmap vocab_tree_builder --database_path db --vocab_tree_path tree.bin --num_visual_words 32768
colmap vocab_tree_matcher --database_path db --vocab_tree_path tree.bin \
    --VocabTreeMatching.num_nearest_neighbors 30
```

---

## 2026-05-21 — COLMAP 3.13 GPU flags are not SiftExtraction/SiftMatching

**Context:** COLMAP documentation and older scripts use `--SiftExtraction.use_gpu 1`
and `--SiftMatching.use_gpu 1`. These fail with "unrecognised option" in COLMAP 3.13.0.

**Correct flags in COLMAP 3.13:**
```bash
--FeatureExtraction.use_gpu 1   # was: --SiftExtraction.use_gpu
--FeatureMatching.use_gpu 1     # was: --SiftMatching.use_gpu
```

`--SiftExtraction.max_num_features` is still valid (unchanged).

**File path:** `scripts/06_colmap_per_cam.sh`, `scripts/07_colmap_merge.sh`

---

## 2026-05-21 — prep_frames.py has a hidden --target 100 that silently subsamples

**Context:** `04_filter_blur.sh` called `prep_frames.py --frames <dir> --threshold T`.
Expected: frames above threshold copied to output with original filenames.
Got: exactly 101 files (100 frames + contact_sheet.jpg) named `frame_00001.jpg` through
`frame_00100.jpg` — all camera prefixes (px9_, a15_, gp_front_) were destroyed.

**Root cause:** `prep_frames.py` is a full pipeline tool for photo-shoot workflows.
It has a hidden default `--target 100` that subsamples blur-filtered frames down to 100,
then renames them sequentially. It also generates a contact sheet. None of that is useful
for video-derived frame pipelines where filenames carry camera identity.

**Fix:** Replaced `prep_frames.py` in `04_filter_blur.sh` with inline Python using
`cv2.Laplacian(gray, cv2.CV_64F).var()`. Copies only files that exceed threshold,
preserves original filename. No subsampling, no contact sheet.

**Rule:** Never use `prep_frames.py` for blur-only filtering on video-derived frames.
The `--threshold` flag alone doesn't bypass the subsampling behavior.

---

## 2026-05-21 — Laplacian blur scores are NOT cross-camera comparable

**Context:** Setting a single `--threshold 40` for all cameras produced:
- pixel9: 78/854 kept (9%) — too strict
- samsung_a15: 0/854 kept (0%) — completely wrong
- gopro_max: 3328/3416 kept (97%) — too permissive

**Root cause:** Laplacian variance is NOT calibrated across cameras. GoPro Max perspective
crops are extracted via ffmpeg v360 with Lanczos interpolation — the resampling ringing
artificially inflates sharpness scores by ~10-15× compared to native phone footage.

**Calibrated distributions (this capture, 2026-05-21):**
| Camera | min | p10 | median | p90 | max |
|---|---|---|---|---|---|
| pixel9 | 2.1 | 4.3 | 15.3 | 41.4 | 64.1 |
| samsung_a15 | 4.7 | 8.2 | 12.9 | 20.9 | 37.4 |
| gopro_max | 24.6 | 57.1 | 213.6 | 399.1 | 571.7 |

**Thresholds used:** pixel9=5 (→ 739/854), a15=5 (→ 844/854), gopro=50 (→ 3195/3416).

**Rule:** Always probe the per-camera distribution before setting a threshold. Run:
```bash
./04_filter_blur.sh --cam <camera> --threshold 5  # start permissive, calibrate up
```
Each camera needs its own threshold. A unified threshold will fail for at least one camera.

---

## 2026-05-21 — Pixel 9 is 60fps not 120fps (label vs reality)

**Context:** The camera_manifest.json initially noted "120fps" based on the
metadata field `com.android.capture.fps: 60.000000` — but the actual video
stream is `59.84 fps, 120 tbr`. The 120 tbr is the time-base rate (the
half-frame container timestamp granularity), not the actual recording FPS.

**Reality:** Pixel 9 is recording at ~60fps (not 120fps). This is still 30×
higher than needed for SfM (we'll decimate to 2fps). The 7:07 clip at 60fps
yields ~25,554 frames; at 2fps extraction = ~854 frames. Consistent with earlier
estimates.

**Implication for field guide:** Recommend recording at 60fps on future captures
(not 120fps) — but the current footage is fine, just at 60fps not 120fps.
