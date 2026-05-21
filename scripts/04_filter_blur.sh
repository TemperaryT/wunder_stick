#!/usr/bin/env bash
# Phase 04: Blur cull using inline OpenCV Laplacian variance filter.
# Outputs: 04_filtered/<cam>/ (kept frames only; original filenames preserved)
#
# Usage: ./04_filter_blur.sh [--threshold <float>] [--cam <pixel9|samsung_a15|gopro_max|all>]
#
# Default threshold: 40 (Laplacian variance — higher = sharper required)
# Lower threshold = keep more frames (be permissive), higher = stricter
# NOTE: threshold is NOT cross-camera comparable — GoPro crops score ~10× higher than
# phone frames due to Lanczos ringing from v360 resampling. Calibrate per-camera.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

THRESHOLD=40
TARGET_CAM="all"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --threshold) THRESHOLD="$2"; shift ;;
        --cam) TARGET_CAM="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

FRAMES_DIR="${ROOT}/03_frames"
FILTERED_DIR="${ROOT}/04_filtered"

mkdir -p "${FILTERED_DIR}/_rejected"

filter_cam() {
    local cam="$1"
    local in_dir="${FRAMES_DIR}/${cam}"
    local out_dir="${FILTERED_DIR}/${cam}"

    require_frames "${in_dir}" "${cam} source frames"
    local total
    total=$(count_frames "${in_dir}")
    mkdir -p "${out_dir}"

    echo "=== Blur-culling ${cam} (threshold=${THRESHOLD}) ==="
    activate_env fselect
    # Inline Laplacian blur filter — preserves original filenames, no subsampling target.
    # cv2 is available in fselect env (installed with opencv via COLMAP deps).
    python3 - <<PYEOF
import cv2, os, shutil, sys
in_dir  = "${in_dir}"
out_dir = "${out_dir}"
threshold = float("${THRESHOLD}")
files = sorted(f for f in os.listdir(in_dir) if f.lower().endswith(('.jpg', '.jpeg', '.png')))
kept = 0
for fname in files:
    src = os.path.join(in_dir, fname)
    img = cv2.imread(src, cv2.IMREAD_GRAYSCALE)
    if img is None:
        print(f"  WARN: could not read {fname}", file=sys.stderr)
        continue
    score = cv2.Laplacian(img, cv2.CV_64F).var()
    if score >= threshold:
        shutil.copy2(src, os.path.join(out_dir, fname))
        kept += 1
print(f"blur filter: {len(files)} → {kept} frames (threshold={threshold})")
PYEOF

    local kept
    kept=$(count_frames "${out_dir}")
    local rejected=$(( total - kept ))
    local pct=0
    [[ "${total}" -gt 0 ]] && pct=$((kept * 100 / total))
    echo "  Kept: ${kept}/${total} (${pct}%) — rejected: ${rejected}"

    if [[ "${pct}" -lt 50 ]]; then
        echo "  WARNING: <50% kept — threshold may be too strict for this camera."
    fi
    if [[ "${pct}" -gt 95 ]]; then
        echo "  WARNING: >95% kept — threshold may be too permissive."
    fi
}

if [[ "${TARGET_CAM}" == "all" ]]; then
    for cam in pixel9 samsung_a15 gopro_max; do
        filter_cam "${cam}"
    done
else
    filter_cam "${TARGET_CAM}"
fi

echo ""
echo "=== Phase 04 complete ==="
summary=""
for cam in pixel9 samsung_a15 gopro_max; do
    [[ -d "${FILTERED_DIR}/${cam}" ]] || continue
    n=$(count_frames "${FILTERED_DIR}/${cam}")
    echo "  ${cam}: ${n} frames kept"
    summary="${summary}${cam}=${n} "
done
echo ""
echo "NEXT: Run 05_mask_moving.sh (or skip to 06 if scene has no moving objects)."

commit_phase "phase-04-blur-cull" "threshold=${THRESHOLD}; ${summary}"
