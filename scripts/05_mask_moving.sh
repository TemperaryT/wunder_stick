#!/usr/bin/env bash
# Phase 05: Moving-object masking.
# Outputs: 05_masked/<cam>/ (symlinks or copies of frames) + 05_masked/masks/<cam>/ (binary PNGs)
#
# Usage: ./05_mask_moving.sh [--cam <pixel9|samsung_a15|gopro_max|all>]
#                            [--method <mog2|replicate>]
#                            [--skip-if-static]  # bypass entirely if scene has no movers
#
# Methods:
#   mog2      (default) OpenCV MOG2 background subtraction — free, good for static-cam scenes
#   replicate Grounded-SAM-2 via Replicate API — text-prompted, handles arbitrary movers
#             Requires: REPLICATE_API_TOKEN env var, pip install replicate in active env
#
# If the scene has no moving objects: run with --skip-if-static to create pass-through
# symlinks (04_filtered/ → 05_masked/) without generating any masks.
#
# COLMAP integration: pass --ImageReader.mask_path 05_masked/masks/<cam>/ in Phase 06.
# Mask format: binary PNG, white=keep (255), black=mask (0), same basename as image.
#
# Inspection after run:
#   ls -1 05_masked/pixel9/ | wc -l          # should match 04_filtered/pixel9/ count
#   ls -1 05_masked/masks/pixel9/ | wc -l    # should match frame count
#   display 05_masked/masks/pixel9/<first>.png  # or: feh, eog, etc.
# Expected: masks are mostly white with black blobs on workers/vehicles.
# Failure: all-black masks = over-masking; all-white = method didn't fire.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

TARGET_CAM="all"
METHOD="mog2"
SKIP_IF_STATIC=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cam) TARGET_CAM="$2"; shift ;;
        --method) METHOD="$2"; shift ;;
        --skip-if-static) SKIP_IF_STATIC=1 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

FILTERED_DIR="${ROOT}/04_filtered"
MASKED_DIR="${ROOT}/05_masked"
MASKS_DIR="${MASKED_DIR}/masks"

mkdir -p "${MASKED_DIR}" "${MASKS_DIR}"

# ------------------------------------------------------------------
# Static-scene passthrough: symlink frames, no actual masking
# ------------------------------------------------------------------
if [[ "${SKIP_IF_STATIC}" -eq 1 ]]; then
    echo "=== Phase 05: STATIC SCENE — pass-through (no masks generated) ==="
    for cam in pixel9 samsung_a15 gopro_max; do
        [[ "${TARGET_CAM}" != "all" && "${TARGET_CAM}" != "${cam}" ]] && continue
        [[ -d "${FILTERED_DIR}/${cam}" ]] || continue
        local_masked="${MASKED_DIR}/${cam}"
        mkdir -p "${local_masked}"
        for f in "${FILTERED_DIR}/${cam}"/*.jpg; do
            [[ -f "$f" ]] || continue
            ln -sf "$(realpath "$f")" "${local_masked}/$(basename "$f")" 2>/dev/null || \
                cp "$f" "${local_masked}/$(basename "$f")"
        done
        n=$(count_frames "${local_masked}")
        echo "  ${cam}: ${n} frames linked (no masks)"
    done
    echo ""
    echo "NOTE: No mask directory created — Phase 06 must omit --ImageReader.mask_path"
    commit_phase "phase-05-mask" "method=passthrough; skip-if-static"
    exit 0
fi

# ------------------------------------------------------------------
# MOG2 background subtraction
# ------------------------------------------------------------------
mask_mog2() {
    local cam="$1"
    local in_dir="${FILTERED_DIR}/${cam}"
    local out_dir="${MASKED_DIR}/${cam}"
    local mask_dir="${MASKS_DIR}/${cam}"

    require_frames "${in_dir}" "${cam} filtered frames"
    mkdir -p "${out_dir}" "${mask_dir}"

    echo "=== MOG2 masking: ${cam} ==="
    activate_env fselect

    python3 - <<PYEOF
import cv2, os, shutil, sys
import numpy as np

in_dir   = "${in_dir}"
out_dir  = "${out_dir}"
mask_dir = "${mask_dir}"

files = sorted(f for f in os.listdir(in_dir) if f.lower().endswith(('.jpg','.jpeg')))
if not files:
    print("No frames found", file=sys.stderr)
    sys.exit(1)

# MOG2 operates on sorted frame sequences — works best when frames are temporally ordered.
# For video-derived frames this is always true (filename sort = capture order).
mog2 = cv2.createBackgroundSubtractorMOG2(
    history=50,        # frames to build background model
    varThreshold=40,   # higher = less sensitive
    detectShadows=False
)

for fname in files:
    src = os.path.join(in_dir, fname)
    img = cv2.imread(src)
    if img is None:
        print(f"  WARN: cannot read {fname}", file=sys.stderr)
        continue

    fg_mask = mog2.apply(img)

    # Morphological cleanup: dilate to cover full object, then close holes
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_DILATE, kernel, iterations=2)
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_CLOSE, kernel, iterations=1)

    # COLMAP mask convention: white (255) = keep, black (0) = mask out
    colmap_mask = cv2.bitwise_not(fg_mask)

    # Save mask as PNG (lossless — important for binary masks)
    mask_fname = os.path.splitext(fname)[0] + ".png"
    cv2.imwrite(os.path.join(mask_dir, mask_fname), colmap_mask)

    # Copy frame to out_dir (symlinks would be cleaner but copy is safer across filesystems)
    shutil.copy2(src, os.path.join(out_dir, fname))

print(f"MOG2: {len(files)} frames processed → masks in {mask_dir}")
PYEOF

    local n
    n=$(count_frames "${out_dir}")
    local nm
    nm=$(find "${mask_dir}" -name "*.png" | wc -l || echo 0)
    echo "  ${cam}: ${n} frames, ${nm} masks"
}

# ------------------------------------------------------------------
# Replicate Grounded-SAM-2 (cloud inference)
# ------------------------------------------------------------------
mask_replicate() {
    local cam="$1"
    local in_dir="${FILTERED_DIR}/${cam}"
    local out_dir="${MASKED_DIR}/${cam}"
    local mask_dir="${MASKS_DIR}/${cam}"

    require_frames "${in_dir}" "${cam} filtered frames"
    mkdir -p "${out_dir}" "${mask_dir}"

    [[ -n "${REPLICATE_API_TOKEN:-}" ]] || {
        echo "ERROR: REPLICATE_API_TOKEN not set. Export it before running with --method replicate." >&2
        echo "  Cost estimate: ~\$0.01/image × $(count_frames "${in_dir}") frames = ~\$$(python3 -c "print(round($(count_frames "${in_dir}") * 0.01, 2))")" >&2
        exit 1
    }

    activate_env fselect
    require_python_module replicate "pip install replicate"

    echo "=== Replicate Grounded-SAM-2: ${cam} ==="
    echo "  Prompt: 'person, worker, forklift, vehicle in motion, machinery in motion'"

    python3 - <<PYEOF
import replicate, cv2, os, shutil, sys, base64, urllib.request
import numpy as np
from pathlib import Path

in_dir   = "${in_dir}"
out_dir  = "${out_dir}"
mask_dir = "${mask_dir}"
PROMPT   = "person, worker, forklift, vehicle in motion, machinery in motion"

files = sorted(f for f in os.listdir(in_dir) if f.lower().endswith(('.jpg','.jpeg')))
print(f"Processing {len(files)} frames via Replicate Grounded-SAM-2...")

for i, fname in enumerate(files):
    src = os.path.join(in_dir, fname)
    with open(src, "rb") as fh:
        img_b64 = "data:image/jpeg;base64," + base64.b64encode(fh.read()).decode()

    output = replicate.run(
        "schananas/grounded_sam:latest",
        input={"image": img_b64, "query": PROMPT}
    )

    # output is expected to be a mask image URL or base64
    mask_fname = os.path.splitext(fname)[0] + ".png"
    mask_out = os.path.join(mask_dir, mask_fname)

    if isinstance(output, str) and output.startswith("http"):
        urllib.request.urlretrieve(output, mask_out)
    elif isinstance(output, str) and output.startswith("data:"):
        raw = base64.b64decode(output.split(",", 1)[1])
        with open(mask_out, "wb") as mf:
            mf.write(raw)
    else:
        # Fallback: write an all-white (keep-all) mask
        img = cv2.imread(src)
        h, w = img.shape[:2]
        cv2.imwrite(mask_out, np.ones((h, w), dtype=np.uint8) * 255)
        print(f"  WARN: unexpected output type for {fname}, wrote pass-through mask", file=sys.stderr)

    shutil.copy2(src, os.path.join(out_dir, fname))
    if (i + 1) % 50 == 0:
        print(f"  {i+1}/{len(files)} done")

print(f"Replicate: {len(files)} frames processed")
PYEOF
}

# ------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------
run_cam() {
    local cam="$1"
    case "${METHOD}" in
        mog2)      mask_mog2 "${cam}" ;;
        replicate) mask_replicate "${cam}" ;;
        *) echo "ERROR: unknown method '${METHOD}'" >&2; exit 1 ;;
    esac
}

if [[ "${TARGET_CAM}" == "all" ]]; then
    for cam in pixel9 samsung_a15 gopro_max; do
        run_cam "${cam}"
    done
else
    run_cam "${TARGET_CAM}"
fi

echo ""
echo "=== Phase 05 complete (method=${METHOD}) ==="
summary=""
for cam in pixel9 samsung_a15 gopro_max; do
    [[ -d "${MASKED_DIR}/${cam}" ]] || continue
    n=$(count_frames "${MASKED_DIR}/${cam}")
    nm=$(find "${MASKS_DIR}/${cam}" -name "*.png" 2>/dev/null | wc -l || echo 0)
    echo "  ${cam}: ${n} frames, ${nm} masks"
    summary="${summary}${cam}=${n} "
done
echo ""
echo "NEXT: Run 06_colmap_per_cam.sh"
echo "      Pass --ImageReader.mask_path ${MASKS_DIR}/<cam> to COLMAP (if masks generated)"

commit_phase "phase-05-mask" "method=${METHOD}; ${summary}"
