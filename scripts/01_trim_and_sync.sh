#!/usr/bin/env bash
# Phase 01: Compute audio sync offsets and produce trimmed, time-aligned videos.
# Outputs: 01_edits/*_trimmed.mp4 + 01_edits/sync_offsets.json
#
# Usage: ./01_trim_and_sync.sh [--skip-sync] [--end-time <seconds>]
#
# --skip-sync   Use existing sync_offsets.json instead of recomputing
# --end-time    Override end trim point (seconds from MASTER start). Default: auto from shortest.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

EDITS_DIR="${ROOT}/01_edits"
RAW_DIR="${ROOT}/00_raw"
OFFSETS_FILE="${EDITS_DIR}/sync_offsets.json"

SKIP_SYNC=0
END_TIME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-sync) SKIP_SYNC=1 ;;
        --end-time) END_TIME="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "${EDITS_DIR}"

# --- Step 1: Compute sync offsets ---
PIXEL9_VID="${RAW_DIR}/pixel9/PXL_mid_cam_front_right.mp4"
A15_VID="${RAW_DIR}/samsung_a15/A15_lower_cam_rear_right.mp4"
GOPRO_VID="${RAW_DIR}/gopro_max/GS010513.360"

if [[ "${SKIP_SYNC}" -eq 0 ]]; then
    echo "=== Computing audio sync offsets ==="
    activate_env fselect
    require_python_module scipy "conda install -n fselect -c conda-forge scipy"
    require_python_module numpy "conda install -n fselect -c conda-forge numpy"
    python3 "${SCRIPT_DIR}/lib/audio_sync.py" \
        --master "${PIXEL9_VID}" \
        --targets "${A15_VID},${GOPRO_VID}" \
        --master-key pixel9 \
        --out "${OFFSETS_FILE}" \
        --duration 120
else
    echo "=== Using existing sync_offsets.json ==="
    [[ -f "${OFFSETS_FILE}" ]] || { echo "ERROR: ${OFFSETS_FILE} not found"; exit 1; }
fi

echo ""
echo "Offsets:"
cat "${OFFSETS_FILE}"
echo ""

# Read offsets
pixel9_offset=0.0
a15_offset=$(python3 -c "import json; d=json.load(open('${OFFSETS_FILE}')); print(d.get('A15_lower_cam_rear_right', d.get('samsung_a15', 0.0)))")
gopro_offset=$(python3 -c "import json; d=json.load(open('${OFFSETS_FILE}')); print(d.get('GS010513', d.get('gopro_max', 0.0)))")

echo "pixel9_offset=${pixel9_offset}s  a15_offset=${a15_offset}s  gopro_offset=${gopro_offset}s"

# --- Step 2: Compute end time (shortest camera after alignment) ---
get_duration() {
    ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null | head -1
}

pixel9_dur=$(get_duration "${PIXEL9_VID}")
a15_dur=$(get_duration "${A15_VID}")
gopro_dur=$(get_duration "${GOPRO_VID}")

# Effective duration from master's t=0 for each camera.
# cam_ss = how many seconds we skip at the start of each cam to align with Pixel9.
# effective_dur = cam_dur - cam_ss  (remaining content after skipping).
a15_ss_preview=$(python3 -c "print(max(0, -${a15_offset}))")
gopro_ss_preview=$(python3 -c "print(max(0, -${gopro_offset}))")
a15_effective=$(python3 -c "print(${a15_dur} - ${a15_ss_preview})")
gopro_effective=$(python3 -c "print(${gopro_dur} - ${gopro_ss_preview})")

shortest=$(python3 -c "print(min(${pixel9_dur}, ${a15_effective}, ${gopro_effective}))")

if [[ -n "${END_TIME}" ]]; then
    clip_end="${END_TIME}"
else
    clip_end="${shortest}"
fi

echo "Clip duration: ${clip_end}s (min of all cameras' usable overlap)"

# --- Step 3: Trim each camera losslessly ---
# fmt: optional ffmpeg -f <format> override (needed for proprietary extensions like .360)
trim_video() {
    local input="$1" output="$2" ss="$3" end="$4" fmt="${5:-}"
    echo "Trimming: $(basename "${input}") → $(basename "${output}") [ss=${ss}s, dur=${end}s]"
    local fmt_flag=()
    [[ -n "${fmt}" ]] && fmt_flag=(-f "${fmt}")
    ffmpeg -y \
        -ss "${ss}" \
        -i "${input}" \
        -t "${end}" \
        -c copy \
        "${fmt_flag[@]}" \
        "${output}"
}

# Pixel 9: master, starts at 0
trim_video "${PIXEL9_VID}" "${EDITS_DIR}/pixel9_trimmed.mp4" "0" "${clip_end}"

# Samsung A15: if offset positive, A15 started LATER — skip its first |offset| seconds
a15_ss=$(python3 -c "print(max(0, -${a15_offset}))")
trim_video "${A15_VID}" "${EDITS_DIR}/samsung_a15_trimmed.mp4" "${a15_ss}" "${clip_end}"

# GoPro Max: .360 is a GoPro-proprietary MP4 container.
# Requires -f mp4 and explicit stream mapping — the proprietary data tracks
# (gpmd/tmcd/fdsc) don't mux cleanly into mp4 and corrupt the output.
# We keep both video streams (front+back EAC lenses) and the main AAC audio only.
gopro_ss=$(python3 -c "print(max(0, -${gopro_offset}))")
echo "Trimming: $(basename "${GOPRO_VID}") → gopro_max_trimmed.360 [ss=${gopro_ss}s, dur=${clip_end}s]"
ffmpeg -y \
    -ss "${gopro_ss}" \
    -i "${GOPRO_VID}" \
    -t "${clip_end}" \
    -map 0:v \
    -map 0:a:0 \
    -c copy \
    -f mp4 \
    "${EDITS_DIR}/gopro_max_trimmed.360"

echo ""
echo "=== Phase 01 complete ==="
echo "Trimmed files in ${EDITS_DIR}/"
echo "  pixel9_trimmed.mp4"
echo "  samsung_a15_trimmed.mp4"
echo "  gopro_max_trimmed.360"
echo ""
echo "NEXT STEP: Verify sync manually by spot-checking frame 1 of each output at the same timestamp."
echo "  ffplay 01_edits/pixel9_trimmed.mp4 &"
echo "  ffplay 01_edits/samsung_a15_trimmed.mp4 &"

commit_phase "phase-01-trim-sync" \
    "offsets a15=${a15_offset}s gopro=${gopro_offset}s; clip=${clip_end}s"
