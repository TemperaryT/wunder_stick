# GoPro Max .360 → Equirectangular Conversion

## Why this is a separate doc

The GoPro Max `.360` file is **not standard equirectangular video**. It is a
proprietary container that packs both lenses as separate EAC (Equi-Angular Cubemap)
HEVC streams (2272×736 each in our capture). To use the footage for SfM/3DGS, we
need a proper equirectangular MP4 — and how to get there from `.360` is the single
biggest unknown in the pipeline.

The current `scripts/02_extract_360_crops.sh` uses `ffmpeg -vf v360=eac:equirect`
which **might work** for our file but is known to be unreliable across GoPro Max
firmware versions because GoPro's lens-specific stitching parameters are not
preserved in the .360 file itself. ffmpeg can do the geometric EAC→equirect
projection but does not know the per-lens distortion correction the camera applies.

## Decision criteria

The "right" conversion is the one that produces:

1. **No visible seam** between the two lenses (or a very faint one at the
   horizontal edges only)
2. **No mirrored/flipped half** — a known failure mode when stream mapping is wrong
3. **Geometric stability** — a straight horizontal line stays straight after the
   equirect → perspective crop in Phase 02 step 2
4. **COLMAP feature density** in the crops at least matches the phone cameras
   (compare feature counts per frame after running 06)

## Options to experiment with

In rough priority order. Document the chosen path below in the "Decision" section
once we've tested.

### Option 1 — GoPro Player (Windows main) — PRIMARY PATH

**The reference implementation.** GoPro's own desktop app uses the camera's
calibration to produce a properly-stitched equirect MP4. This is the ground truth
that any other approach should be compared against.

Procedure:

1. Copy `00_raw/gopro_max/GS010513.360` to Windows main via Tailscale
   ```bash
   rsync -aP 00_raw/gopro_max/GS010513.360 main:/c/Users/<user>/Desktop/wunder_stick/
   ```
2. Open in GoPro Player → "Export" → select 5.6K equirectangular MP4 (H.264 or HEVC)
3. Copy back to WSL: `01_edits/gopro_max_equirect.mp4`
4. Skip the ffmpeg EAC→equirect step; jump straight to perspective crops
5. Update `02_extract_360_crops.sh` to detect the pre-stitched equirect file and use it

**Pros:** known-good lens calibration, no guesswork
**Cons:** manual step, requires Windows main session, GoPro Player export can be slow

### Option 2 — ffmpeg v360 EAC→equirect — CURRENT SCRIPT

What `02_extract_360_crops.sh` currently does:

```bash
ffmpeg -i input.360 -vf "v360=eac:equirect:interp=lanczos:w=5760:h=2880" out.jpg
```

**Pros:** scriptable, fast, no manual step
**Cons:** does NOT apply GoPro's lens calibration; seam visibility depends on
firmware/lens variance; some .360 files have an inverted second stream

Worth a 10s test run first (`--test-clip` flag). If the test equirect frame looks
clean, this path is fine and we skip Option 1.

### Option 3 — `max2sphere` (open-source CLI)

Third-party tool that specifically targets GoPro Max .360 files. Approximates the
GoPro stitching algorithm.

- Repo: https://github.com/trek-view/max2sphere (verify before relying)
- Status: untested in this project

### Option 4 — gopro-tools / gopro2gpx ecosystem

Various community tools. Generally aimed at metadata extraction, but some include
projection conversion. Lowest priority.

### Option 5 — Skip equirect, use raw EAC streams directly

The .360 has TWO video streams. We could extract each as a fisheye, treat them as
two cameras, and let COLMAP handle them as separate sensors with their own
intrinsics. Avoids the stitching problem entirely.

**Cons:** doubles the GoPro frame count, requires per-fisheye distortion model
(approximate fisheye intrinsics), may confuse COLMAP loop closure. Defer unless
all other options fail.

## Test protocol

When evaluating an option:

1. Pick a 10-second segment with **known straight lines** in view (industrial
   scenes have plenty — beams, pipes, edges of equipment).
2. Run the conversion, dump frame 5.
3. Open frame in any image viewer. Eyeball:
   - Are the two halves seamlessly joined?
   - Are horizontal real-world lines horizontal in the upper half of the image?
     (Equirect curves them as they approach the poles, which is correct.)
4. Run `02_extract_360_crops.sh extract_crop` for yaw=0 to produce a `front` crop.
5. Check the `front` crop for distortion artifacts.
6. If all four crops look good, run `06_colmap_per_cam.sh --cam gopro_max` on a
   short clip and check `stats.json` for feature counts comparable to phone cameras.

## Decision

_To be filled in after Phase C experiments. Current placeholder: try Option 2
(ffmpeg) first via `--test-clip`; fall back to Option 1 (GoPro Player) if seam is
visible or crops fail the COLMAP gate._

| Date | Option tried | Result | Decision |
|---|---|---|---|
| (TBD) | Option 2 (ffmpeg) | (test pending) | (pending) |
| (TBD) | Option 1 (GoPro Player) | (test pending) | (pending) |

## See also

- `02_runbook.md` — Phase 02 commands
- `scripts/02_extract_360_crops.sh` — current ffmpeg implementation
- `00_raw/camera_manifest.json` — GoPro Max capture metadata
