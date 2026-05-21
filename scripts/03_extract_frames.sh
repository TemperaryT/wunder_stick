#!/usr/bin/env bash
# Phase 03: Extract frames from trimmed videos at target FPS.
# GoPro crops are collected from 02_360_extracted/ into 03_frames/gopro_max/.
#
# Usage: ./03_extract_frames.sh [--fps <n>] [--width <px>]
#
# Defaults: fps=2, width=1920
# Pixel 9 is 120fps source — at fps=2 we get ~854 frames from a 427s clip.
# This gives plenty of frames without overwhelming COLMAP.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

TARGET_FPS=2
TARGET_WIDTH=1920

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fps) TARGET_FPS="$2"; shift ;;
        --width) TARGET_WIDTH="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

EDITS_DIR="${ROOT}/01_edits"
FRAMES_DIR="${ROOT}/03_frames"

mkdir -p "${FRAMES_DIR}/pixel9" "${FRAMES_DIR}/samsung_a15" "${FRAMES_DIR}/gopro_max"

extract_video_frames() {
    local cam="$1" input="$2" out_prefix="$3"
    local out_dir="${FRAMES_DIR}/${cam}"
    [[ -f "${input}" ]] || { echo "ERROR: ${input} not found"; exit 1; }
    echo "Extracting ${cam} at ${TARGET_FPS}fps, width=${TARGET_WIDTH}px..."
    ffmpeg -y \
        -i "${input}" \
        -vf "fps=${TARGET_FPS},scale=${TARGET_WIDTH}:-2:flags=lanczos" \
        -q:v 2 \
        "${out_dir}/${out_prefix}_%06d.jpg"
    local n
    n=$(count_frames "${out_dir}")
    echo "  → ${n} frames"
}

# Phone cameras — extract from trimmed mp4
extract_video_frames "pixel9"     "${EDITS_DIR}/pixel9_trimmed.mp4"     "px9"
extract_video_frames "samsung_a15" "${EDITS_DIR}/samsung_a15_trimmed.mp4" "a15"

# GoPro Max — copy/symlink from 02_360_extracted/ crops into 03_frames/gopro_max/
# Frames already exist from phase 02. Just copy them flat with cam-prefixed names.
echo "Collecting GoPro Max perspective crop frames..."
GP_OUT="${FRAMES_DIR}/gopro_max"
GP_SRC="${ROOT}/02_360_extracted"

for view in front right left tilted_up; do
    src_dir="${GP_SRC}/${view}"
    [[ -d "${src_dir}" ]] || continue
    n_src=$(count_frames "${src_dir}")
    [[ "${n_src}" -eq 0 ]] && continue
    echo "  Copying ${n_src} frames from ${view}/..."
    # Files in src already named gp_<view>_NNNNNN.jpg — just copy
    cp "${src_dir}"/gp_*.jpg "${GP_OUT}/" 2>/dev/null || true
done

echo ""
echo "=== Phase 03 complete ==="
n_pixel9=$(count_frames "${FRAMES_DIR}/pixel9")
n_a15=$(count_frames "${FRAMES_DIR}/samsung_a15")
n_gopro=$(count_frames "${FRAMES_DIR}/gopro_max")
echo "  pixel9:     ${n_pixel9} frames"
echo "  samsung_a15: ${n_a15} frames"
echo "  gopro_max:  ${n_gopro} frames"
echo ""
echo "NEXT: Run 04_filter_blur.sh to cull blurry frames."

commit_phase "phase-03-extract-frames" \
    "fps=${TARGET_FPS} width=${TARGET_WIDTH}; pixel9=${n_pixel9} a15=${n_a15} gopro=${n_gopro}"
