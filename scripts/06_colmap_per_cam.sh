#!/usr/bin/env bash
# Phase 06: Per-camera COLMAP SfM reconstruction.
# Runs COLMAP feature_extractor → vocab_tree_matcher → GLOMAP global mapper.
# Outputs: 06_colmap_per_cam/<cam>/sparse/0/ + stats.json
#
# Usage: ./06_colmap_per_cam.sh [--cam <pixel9|samsung_a15|gopro_max|all>]
#                               [--no-masks]         # skip mask_path even if 05_masked/ exists
#                               [--colmap-only]      # skip GLOMAP, use COLMAP incremental mapper
#                               [--matcher sequential|vocab_tree]  # default: vocab_tree
#                               [--overlap <int>]    # sequential_matcher overlap (default 30)
#                               [--nn <int>]         # vocab_tree nearest neighbors (default 30)
#
# Matcher choice:
#   vocab_tree  (default) — builds a vocabulary tree from image features, then matches
#               each frame to its most visually similar frames globally.
#               Use for any scene where camera moves significantly between shots.
#   sequential  — matches frames by sequence order (fast, but breaks for fast camera motion).
#               Use only for slow pans or as a quick sanity check.
#
# Camera models used:
#   pixel9, samsung_a15 : SIMPLE_RADIAL (phone, single focal length + 1 radial distortion)
#   gopro_max           : OPENCV per image (MIXED_CAMERAS=1 — 4 crop FOVs differ slightly)
#
# Quality gate (via lib/colmap_stats.py):
#   registered_pct >= 85%, num_points3d >= 10k, reproj_err_mean <= 1.5px
#
# Inspection after run:
#   cat 06_colmap_per_cam/<cam>/stats.json          # quality gate results
#   colmap gui --database_path 06_colmap_per_cam/<cam>/database.db \
#              --image_path 05_masked/<cam>/         # visual SfM viewer (needs display)
#
# Expected: registered_pct 70-95%, reproj_err < 1.0px.
# Failure: registered_pct < 30% → camera moving too fast (lower fps or stricter blur cull).
# Failure: registered_pct = 0% → camera model mismatch.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

TARGET_CAM="all"
NO_MASKS=0
COLMAP_ONLY=0
MATCHER="vocab_tree"
OVERLAP=30
NN=30

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cam)         TARGET_CAM="$2"; shift ;;
        --no-masks)    NO_MASKS=1 ;;
        --colmap-only) COLMAP_ONLY=1 ;;
        --matcher)     MATCHER="$2"; shift ;;
        --overlap)     OVERLAP="$2"; shift ;;
        --nn)          NN="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

MASKED_DIR="${ROOT}/05_masked"
MASKS_DIR="${MASKED_DIR}/masks"
OUT_BASE="${ROOT}/06_colmap_per_cam"
COLMAP_STATS="${SCRIPT_DIR}/lib/colmap_stats.py"

[[ -f "${COLMAP_STATS}" ]] || { echo "ERROR: colmap_stats.py not found at ${COLMAP_STATS}"; exit 1; }

run_colmap_cam() {
    local cam="$1"
    local cam_model="$2"    # SIMPLE_RADIAL or OPENCV
    local mixed_cams="$3"   # 0 or 1

    local img_dir="${MASKED_DIR}/${cam}"
    # Fall back to 04_filtered if 05_masked not yet run
    [[ -d "${img_dir}" ]] || img_dir="${ROOT}/04_filtered/${cam}"
    require_frames "${img_dir}" "${cam} frames"

    local out_dir="${OUT_BASE}/${cam}"
    local db="${out_dir}/database.db"
    local sparse="${out_dir}/sparse"
    mkdir -p "${out_dir}" "${sparse}"

    # Mask path: use 05_masked/masks/<cam>/ if it exists and --no-masks not set
    local mask_arg=""
    if [[ "${NO_MASKS}" -eq 0 && -d "${MASKS_DIR}/${cam}" ]]; then
        mask_arg="--ImageReader.mask_path ${MASKS_DIR}/${cam}"
    fi

    # Mixed cameras flag (for GoPro multi-view crops with different FOVs)
    local mixed_arg=""
    [[ "${mixed_cams}" -eq 1 ]] && mixed_arg="--ImageReader.single_camera_per_folder 0"

    echo ""
    echo "=== COLMAP Phase 06: ${cam} ==="
    echo "  images:      ${img_dir}"
    echo "  camera_model: ${cam_model}  mixed_cameras: ${mixed_cams}"
    echo "  matcher:     ${MATCHER}"
    [[ "${MATCHER}" == "sequential" ]] && echo "  overlap:     ${OVERLAP}"
    [[ "${MATCHER}" == "vocab_tree" ]] && echo "  nn:          ${NN}"
    [[ -n "${mask_arg}" ]] && echo "  masks:       ${MASKS_DIR}/${cam}"

    activate_env fselect

    # 1. Feature extraction
    echo "--- feature_extractor ---"
    colmap feature_extractor \
        --database_path "${db}" \
        --image_path "${img_dir}" \
        --ImageReader.camera_model "${cam_model}" \
        --ImageReader.single_camera $([[ "${mixed_cams}" -eq 0 ]] && echo 1 || echo 0) \
        ${mixed_arg} \
        ${mask_arg} \
        --FeatureExtraction.use_gpu 1 \
        --SiftExtraction.max_num_features 8192

    # 2. Matching — vocab_tree (default) or sequential
    if [[ "${MATCHER}" == "vocab_tree" ]]; then
        local tree="${out_dir}/vocab_tree.bin"
        echo "--- vocab_tree_builder ---"
        colmap vocab_tree_builder \
            --database_path "${db}" \
            --vocab_tree_path "${tree}" \
            --num_visual_words 32768
        echo "--- vocab_tree_matcher (nn=${NN}) ---"
        colmap vocab_tree_matcher \
            --database_path "${db}" \
            --VocabTreeMatching.vocab_tree_path "${tree}" \
            --VocabTreeMatching.num_nearest_neighbors "${NN}" \
            --FeatureMatching.use_gpu 1
    else
        echo "--- sequential_matcher (overlap=${OVERLAP}) ---"
        colmap sequential_matcher \
            --database_path "${db}" \
            --SequentialMatching.overlap "${OVERLAP}" \
            --FeatureMatching.use_gpu 1
    fi

    # 3. Reconstruct: GLOMAP global mapper (preferred) or COLMAP incremental mapper
    if [[ "${COLMAP_ONLY}" -eq 0 ]]; then
        echo "--- glomap mapper (global) ---"
        glomap mapper \
            --database_path "${db}" \
            --image_path "${img_dir}" \
            --output_path "${sparse}"
    else
        echo "--- colmap mapper (incremental) ---"
        colmap mapper \
            --database_path "${db}" \
            --image_path "${img_dir}" \
            --output_path "${sparse}" \
            --Mapper.num_threads 8
    fi

    # COLMAP/GLOMAP output goes to sparse/0 or sparse/1 etc.
    # Normalize to sparse/0 if mapper produced a different number.
    local best_sparse="${sparse}/0"
    if [[ ! -d "${best_sparse}" ]]; then
        # Pick the subdirectory with the most images.txt lines
        best_sparse=$(find "${sparse}" -mindepth 1 -maxdepth 1 -type d | \
            sort -t/ -k1 | head -1)
    fi

    if [[ ! -d "${best_sparse}" ]]; then
        echo "ERROR: no reconstruction in ${sparse}" >&2
        return 1
    fi

    # Convert to text format so colmap_stats.py can parse it
    colmap model_converter \
        --input_path "${best_sparse}" \
        --output_path "${best_sparse}" \
        --output_type TXT 2>/dev/null || true

    # Create images/ symlink in out_dir so gsplat simple_trainer.py can use this
    # dir directly as --data_dir (expects sparse/0/ + images/ at same level).
    local images_link="${out_dir}/images"
    if [[ ! -e "${images_link}" ]]; then
        ln -s "$(realpath "${img_dir}")" "${images_link}"
        echo "  Symlinked: ${images_link} → ${img_dir}"
    fi

    # 4. Quality gate
    echo "--- quality gate ---"
    python3 "${COLMAP_STATS}" "${best_sparse}" \
        --out "${out_dir}/stats.json" \
        --db "${db}" || {
        echo "  WARNING: quality gate failed for ${cam} — check ${out_dir}/stats.json"
    }
}

# Camera configs: cam_model  mixed_cameras
declare -A CAM_MODEL=( [pixel9]="SIMPLE_RADIAL" [samsung_a15]="SIMPLE_RADIAL" [gopro_max]="OPENCV" )
declare -A CAM_MIXED=( [pixel9]="0"             [samsung_a15]="0"             [gopro_max]="1" )

if [[ "${TARGET_CAM}" == "all" ]]; then
    for cam in pixel9 samsung_a15 gopro_max; do
        run_colmap_cam "${cam}" "${CAM_MODEL[$cam]}" "${CAM_MIXED[$cam]}"
    done
else
    cam="${TARGET_CAM}"
    run_colmap_cam "${cam}" "${CAM_MODEL[$cam]}" "${CAM_MIXED[$cam]}"
fi

echo ""
echo "=== Phase 06 complete ==="
summary=""
for cam in pixel9 samsung_a15 gopro_max; do
    stats_file="${OUT_BASE}/${cam}/stats.json"
    [[ -f "${stats_file}" ]] || continue
    reg=$(python3 -c "import json; d=json.load(open('${stats_file}')); print(d['registered_pct'])" 2>/dev/null || echo "?")
    pts=$(python3 -c "import json; d=json.load(open('${stats_file}')); print(d['num_points3d'])" 2>/dev/null || echo "?")
    err=$(python3 -c "import json; d=json.load(open('${stats_file}')); print(d['reproj_err_mean'])" 2>/dev/null || echo "?")
    echo "  ${cam}: registered=${reg}%  pts3d=${pts}  reproj=${err}px"
    summary="${summary}${cam}=${reg}%reg "
done
echo ""
echo "NEXT: Run 07_colmap_merge.sh (or inspect per-cam models first)"
echo "      Inspect: cat 06_colmap_per_cam/<cam>/stats.json"

commit_phase "phase-06-colmap-per-cam" "${summary}"
