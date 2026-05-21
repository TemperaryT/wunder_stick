# Capture Field Guide — wunder_stick 3-camera rig

For future captures on this pipeline. The 2026-05-20 capture this project was bootstrapped
from worked — but several things would have been easier with this checklist in hand.

## Rig layout

Three cameras, stacked vertically on a single rigid mount, all pointed at the scene
of interest:

| Position | Camera | Role | Lens / FOV |
|---|---|---|---|
| Upper | GoPro Max | 360° wide context | Dual fisheye → equirect |
| Middle | Pixel 9 | Primary high-res, mid-altitude eye-line | Main lens, 4K |
| Lower | Samsung A15 | Low-angle coverage, redundant SfM signal | 1080p |

**Master clock:** Pixel 9. All other cameras get sync-adjusted to it in post via
audio cross-correlation. There is no hardware genlock.

**Why three:** the GoPro provides 360° context COLMAP loves for loop closure; the
Pixel 9 provides high-resolution primary detail; the A15 provides a second
ground-truth viewpoint at a different angle to break SfM ambiguity. Anything fewer
risks sparse coverage; anything more rapidly hits storage + sync complexity.

## Pre-capture checklist

- [ ] All cameras charged to >80%
- [ ] Storage: GoPro ≥64GB free, Pixel ≥40GB free, A15 ≥30GB free
- [ ] Pixel 9 set to 4K @ 60fps (NOT 120fps — see lesson below)
- [ ] A15 set to 1080p @ 30fps (max)
- [ ] GoPro Max set to 5.6K 360 @ 30fps (NOT 50fps — see lesson below)
- [ ] All cameras: airplane mode ON (no notifications)
- [ ] All cameras: stabilization ON if available (you'll throw away frames, but
      shaky frames at 1080p are unusable for SfM)
- [ ] Audio enabled on all three (sync depends on it)
- [ ] Phones tilted ~10° down to avoid all-sky frames
- [ ] Rig secured — any rig-vs-camera relative motion breaks per-cam SfM

## Sync clap protocol

At capture start, with all cameras already recording:

1. Hold a single hand-clap **directly in front of the rig**, ~1m away, at chest height.
2. One sharp clap, then count "one-mississippi-two-mississippi" silently, second clap.
3. Begin capture motion only after the second clap.

The two-clap pattern gives the audio xcorr a backup signal if the first clap is
masked by ambient noise. Plain talking or door-slams will also work as a fallback
correlation peak — see `03_camera_sync_method.md` (TBD) for details.

## Capture motion

For SfM-friendly footage:

- **Slow.** Walking pace, not running.
- **Steady.** No whip-pans. Yaw should take ≥3 seconds per 90°.
- **Loop closure.** End where you started, with the same view. Critical for COLMAP merge.
- **Overlap.** Each "region" of the scene should be visible from ≥3 distinct positions.
- **Avoid pure pan-only motion.** Translation between frames is what enables triangulation.
- **Avoid texture-poor surfaces filling the frame.** SfM has nothing to feature-match.

## Lessons from the 2026-05-20 capture

These are gotchas to fix on the NEXT capture, not problems with the existing data:

| Issue | Impact | Fix for next capture |
|---|---|---|
| Pixel 9 @ 120fps | 3.3GB file, aggressive frame decimation needed | Use 60fps — quarter the data, same SfM result |
| GoPro Max @ 50fps | Higher file size, no SfM benefit | 30fps is plenty at 5.6K |
| Cameras not started simultaneously | A15 is 61s longer than Pixel 9 | Start all three within ~5s; audio xcorr still handles offset but overlap shrinks |
| No sync clap | Cross-correlation works on ambient but is weaker | Two-clap as above |
| LiDAR scan not captured during same session | Cannot ground-truth alignment yet | Run Hovermap scan **during the same walkthrough** if possible |

## Post-capture (operator)

1. Ingest immediately: copy files into `00_raw/<cam>/`, generate sha256, commit.
2. Update `00_raw/camera_manifest.json` with the new shoot's metadata (file paths,
   codec, duration, fps).
3. Note any deviations from this guide in `docs/lessons_learned.md`.

## See also

- `00_pipeline_overview.md` — what happens to the footage after ingest
- `02_runbook.md` — how to run the pipeline
- `lessons_learned.md` — running gotcha log
