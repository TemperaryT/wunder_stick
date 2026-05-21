#!/usr/bin/env bash
# Phase 02: Convert GoPro Max .360 (dual EAC) to equirectangular, then extract
# perspective crops (front, right, left, tilted_up).
#
# Usage: ./02_extract_360_crops.sh [--test-clip] [--no-tilted-up]
#
# --test-clip     Process only first 10s (for fast validation before full run)
# --no-tilted-up  Skip the tilted_up (pitch=+40°) crop

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

EDITS_DIR="${ROOT}/01_edits"
OUT_DIR="${ROOT}/02_360_extracted"
GOPRO_IN="${EDITS_DIR}/gopro_max_trimmed.360"
EQUIRECT_DIR="${OUT_DIR}/equirect"

TEST_CLIP=0
INCLUDE_TILTED=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test-clip) TEST_CLIP=1 ;;
        --no-tilted-up) INCLUDE_TILTED=0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

[[ -f "${GOPRO_IN}" ]] || { echo "ERROR: ${GOPRO_IN} not found. Run 01_trim_and_sync.sh first."; exit 1; }

mkdir -p "${EQUIRECT_DIR}" "${OUT_DIR}/front" "${OUT_DIR}/right" "${OUT_DIR}/left"
[[ "${INCLUDE_TILTED}" -eq 1 ]] && mkdir -p "${OUT_DIR}/tilted_up"

DURATION_FLAG=""
if [[ "${TEST_CLIP}" -eq 1 ]]; then
    DURATION_FLAG="-t 10"
    echo "TEST MODE: processing first 10s only"
fi

# GoPro MAX .360 EAC dual-stream → equirectangular
# The .360 format stores both lenses as EAC in stream 0 and stream 1.
# ffmpeg's v360 filter with input=eac stitches them to equirect when both streams merged.
# We use the first video stream (-map 0:v:0) and rely on GoPro's EAC packing.
# Output: 5760x2880 equirectangular JPEGs (or reduce to 3840x1920 for speed).
EQUIRECT_W=5760
EQUIRECT_H=2880

echo "=== Step 1: EAC → Equirectangular ==="
echo "Input: ${GOPRO_IN}"
echo "Output: ${EQUIRECT_DIR}/ at ${EQUIRECT_W}x${EQUIRECT_H}"

ffmpeg -y \
    -i "${GOPRO_IN}" \
    ${DURATION_FLAG} \
    -map 0:v:0 \
    -vf "v360=eac:equirect:interp=lanczos:w=${EQUIRECT_W}:h=${EQUIRECT_H}" \
    -q:v 2 \
    "${EQUIRECT_DIR}/frame_%06d.jpg"

EQUIRECT_COUNT=$(count_frames "${EQUIRECT_DIR}")
echo "Equirectangular frames: ${EQUIRECT_COUNT}"

# --- Perspective crop helper ---
# v360 equirect→flat parameters:
#   ih_fov / iv_fov: horizontal/vertical FOV of output in degrees
#   yaw / pitch: view direction
extract_crop() {
    local yaw="$1" pitch="$2" label="$3"
    local out_dir="${OUT_DIR}/${label}"
    mkdir -p "${out_dir}"
    echo "Extracting crop: ${label} (yaw=${yaw}° pitch=${pitch}°)"
    ffmpeg -y \
        -framerate 50 \
        -pattern_type glob -i "${EQUIRECT_DIR}/frame_*.jpg" \
        -vf "v360=equirect:flat:ih_fov=120:iv_fov=90:yaw=${yaw}:pitch=${pitch}:interp=lanczos:w=1920:h=1440" \
        -q:v 2 \
        "${out_dir}/gp_${label}_%06d.jpg"
    local n
    n=$(count_frames "${out_dir}")
    echo "  → ${n} frames in ${out_dir}"
}

echo ""
echo "=== Step 2: Extract Perspective Crops ==="
extract_crop 0   0  "front"
extract_crop 90  0  "right"
extract_crop -90 0  "left"
[[ "${INCLUDE_TILTED}" -eq 1 ]] && extract_crop 0 40 "tilted_up"

# Merge naming: copy all crops into 03_frames/gopro_max/ is done by 03_extract_frames.sh
# Here we just produce the per-view directories.

echo ""
echo "=== Phase 02 complete ==="
echo "Crops in ${OUT_DIR}/"
for view in front right left; do
    echo "  ${view}/: $(count_frames "${OUT_DIR}/${view}") frames"
done
[[ "${INCLUDE_TILTED}" -eq 1 ]] && echo "  tilted_up/: $(count_frames "${OUT_DIR}/tilted_up") frames"
echo ""
echo "NOTE: If equirect stitching looks wrong (visible seam, mirrored), the .360 file"
echo "may need GoPro Player on Windows to export a proper equirect MP4 first."
echo "See docs/09_gopro_360_conversion.md for the comparison + fallback procedure."

# Skip phase commit for test-clip runs — those are throwaway validation.
if [[ "${TEST_CLIP}" -eq 0 ]]; then
    front_n=$(count_frames "${OUT_DIR}/front")
    commit_phase "phase-02-gopro-360-crops" \
        "equirect=${EQUIRECT_COUNT}f at ${EQUIRECT_W}x${EQUIRECT_H}; front=${front_n}f"
fi
