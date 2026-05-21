#!/usr/bin/env bash
# Phase 04: Blur cull using prep_frames.py from frame_prep project.
# Outputs: 04_filtered/<cam>/ (kept frames) + 04_filtered/_rejected/ (culled)
#
# Usage: ./04_filter_blur.sh [--threshold <float>] [--cam <pixel9|samsung_a15|gopro_max|all>]
#
# Default threshold: 40 (Laplacian variance — higher = sharper required)
# Lower threshold = keep more frames (be permissive), higher = stricter

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
PREP_FRAMES="${HOME}/projects/automation_server/scripts/prep_frames.py"

[[ -f "${PREP_FRAMES}" ]] || { echo "ERROR: prep_frames.py not found at ${PREP_FRAMES}"; exit 1; }

mkdir -p "${FILTERED_DIR}/_rejected"

filter_cam() {
    local cam="$1"
    local in_dir="${FRAMES_DIR}/${cam}"
    local out_dir="${FILTERED_DIR}/${cam}"
    local reject_dir="${FILTERED_DIR}/_rejected/${cam}"

    require_frames "${in_dir}" "${cam} source frames"
    mkdir -p "${out_dir}" "${reject_dir}"

    echo "=== Blur-culling ${cam} (threshold=${THRESHOLD}) ==="
    activate_env fselect
    python3 "${PREP_FRAMES}" \
        --frames "${in_dir}" \
        --output "${out_dir}" \
        --threshold "${THRESHOLD}" \
        --rejected "${reject_dir}"

    local kept rejected
    kept=$(count_frames "${out_dir}")
    rejected=$(count_frames "${reject_dir}")
    local total=$((kept + rejected))
    local pct=0
    [[ "${total}" -gt 0 ]] && pct=$((kept * 100 / total))
    echo "  Kept: ${kept}/${total} (${pct}%)"

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
