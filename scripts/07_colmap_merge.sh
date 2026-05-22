#!/usr/bin/env bash
# Phase 07: Multi-camera COLMAP merge.
# Strategy A (default): re-run COLMAP on union of all cameras' frames (recommended).
# Strategy B (fallback): colmap model_merger on existing per-cam sparse models.
#
# Usage: ./07_colmap_merge.sh [--strategy <A|B>]
#                             [--no-masks]
#                             [--overlap <int>]  # default 30
#
# Strategy A: Union re-run
#   - Creates a flat images/ dir with ALL frames (cam-prefixed names)
#   - Re-runs feature extraction + sequential_matcher + GLOMAP
#   - MIXED_CAMERAS=1 to handle different camera models in one run
#   - Better global consistency than model merging
#
# Strategy B: Model merger
#   - Uses colmap model_merger on existing 06_colmap_per_cam/<cam>/sparse/0/ dirs
#   - Fast but requires per-cam models to share scale (needs cross-cam frame overlap)
#   - Use only if Strategy A fails or is too slow
#
# Inspection after run:
#   cat 07_colmap_merged/stats.json                 # quality gate
#   wc -l 07_colmap_merged/sparse/0/images.txt      # total registered images
#   cat 07_colmap_merged/merge_strategy.md           # decision record
#
# Expected: registered_pct >= 80% across all cameras, reproj_err < 1.5px.
# Good: if merged model has MORE points3d than sum of per-cam models — cross-cam triangulation working.
# Failure: registered_pct < 50% → cameras not linking up (need overlap frames or sync check).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

STRATEGY="A"
NO_MASKS=0
OVERLAP=30

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strategy) STRATEGY="$2"; shift ;;
        --no-masks) NO_MASKS=1 ;;
        --overlap)  OVERLAP="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

MASKED_DIR="${ROOT}/05_masked"
MASKS_DIR="${MASKED_DIR}/masks"
PER_CAM_DIR="${ROOT}/06_colmap_per_cam"
OUT_DIR="${ROOT}/07_colmap_merged"
IMAGES_DIR="${OUT_DIR}/images"
SPARSE_DIR="${OUT_DIR}/sparse"
COLMAP_STATS="${SCRIPT_DIR}/lib/colmap_stats.py"

mkdir -p "${OUT_DIR}" "${IMAGES_DIR}" "${SPARSE_DIR}"

write_merge_strategy_doc() {
    cat > "${OUT_DIR}/merge_strategy.md" <<EOF
# wunder_stick — Merge Strategy

Date: $(date '+%Y-%m-%d %H:%M')
Strategy: **${STRATEGY}**

## Strategy A — Union re-run (chosen when A)
Re-run COLMAP on the union of all cameras' frames in a single flat directory.
MIXED_CAMERAS=1 handles different camera intrinsics per image.
Sequential matcher with overlap=${OVERLAP}.

## Strategy B — Model merger (chosen when B)
colmap model_merger on existing per-cam sparse/0/ models.
Requires shared scale (needs cross-cam frame overlap or known scale).

## Cameras
- pixel9: SIMPLE_RADIAL, frames from 05_masked/ (or 04_filtered/ fallback)
- samsung_a15: SIMPLE_RADIAL
- gopro_max: OPENCV, MIXED_CAMERAS=1

## Decision
$(if [[ "${STRATEGY}" == "A" ]]; then
    echo "Strategy A chosen (default — better global consistency)."
else
    echo "Strategy B chosen (fallback — faster if per-cam models exist and share scale)."
fi)
EOF
}

# ------------------------------------------------------------------
# Strategy A: Union re-run
# ------------------------------------------------------------------
strategy_a() {
    echo "=== Strategy A: Union re-run ==="

    # Build flat images/ dir with cam-prefixed names (symlinks)
    echo "--- Building union images dir ---"
    local total_linked=0
    for cam in pixel9 samsung_a15 gopro_max; do
        local src_dir="${MASKED_DIR}/${cam}"
        [[ -d "${src_dir}" ]] || src_dir="${ROOT}/04_filtered/${cam}"
        [[ -d "${src_dir}" ]] || { echo "  SKIP ${cam}: no frames found"; continue; }

        local prefix
        case "${cam}" in
            pixel9)      prefix="px9_" ;;
            samsung_a15) prefix="a15_" ;;
            gopro_max)   prefix="gp_" ;;
        esac

        local n=0
        for f in "${src_dir}"/*.jpg; do
            [[ -f "$f" ]] || continue
            local base; base=$(basename "$f")
            ln -sf "$(realpath "$f")" "${IMAGES_DIR}/${prefix}${base}" 2>/dev/null || \
                cp "$f" "${IMAGES_DIR}/${prefix}${base}"
            (( n++ )) || true
        done
        echo "  ${cam}: ${n} frames linked as ${prefix}*"
        (( total_linked += n )) || true
    done
    echo "  Total: ${total_linked} frames in ${IMAGES_DIR}"

    local db="${OUT_DIR}/database.db"

    activate_env fselect

    # Mask path for merged run: need to combine all mask dirs.
    # COLMAP mask_path must point to a single dir containing masks named to match images/.
    # We build a combined masks/ dir with the same prefix scheme.
    local mask_arg=""
    if [[ "${NO_MASKS}" -eq 0 ]]; then
        local merged_masks="${OUT_DIR}/masks"
        local has_masks=0
        mkdir -p "${merged_masks}"
        for cam in pixel9 samsung_a15 gopro_max; do
            [[ -d "${MASKS_DIR}/${cam}" ]] || continue
            local prefix
            case "${cam}" in
                pixel9)      prefix="px9_" ;;
                samsung_a15) prefix="a15_" ;;
                gopro_max)   prefix="gp_" ;;
            esac
            for mf in "${MASKS_DIR}/${cam}"/*.png; do
                [[ -f "$mf" ]] || continue
                ln -sf "$(realpath "$mf")" "${merged_masks}/${prefix}$(basename "$mf")" 2>/dev/null || \
                    cp "$mf" "${merged_masks}/${prefix}$(basename "$mf")"
                has_masks=1
            done
        done
        [[ "${has_masks}" -eq 1 ]] && mask_arg="--ImageReader.mask_path ${merged_masks}"
    fi

    echo "--- feature_extractor (MIXED_CAMERAS) ---"
    colmap feature_extractor \
        --database_path "${db}" \
        --image_path "${IMAGES_DIR}" \
        --ImageReader.camera_model OPENCV \
        --ImageReader.single_camera 0 \
        --ImageReader.single_camera_per_folder 0 \
        ${mask_arg} \
        --FeatureExtraction.use_gpu 1 \
        --SiftExtraction.max_num_features 8192

    echo "--- sequential_matcher (overlap=${OVERLAP}) ---"
    colmap sequential_matcher \
        --database_path "${db}" \
        --SequentialMatching.overlap "${OVERLAP}" \
        --FeatureMatching.use_gpu 1

    echo "--- glomap mapper ---"
    glomap mapper \
        --database_path "${db}" \
        --image_path "${IMAGES_DIR}" \
        --output_path "${SPARSE_DIR}"

    local best_sparse="${SPARSE_DIR}/0"
    if [[ ! -d "${best_sparse}" ]]; then
        best_sparse=$(find "${SPARSE_DIR}" -mindepth 1 -maxdepth 1 -type d | sort | head -1)
    fi

    colmap model_converter \
        --input_path "${best_sparse}" \
        --output_path "${best_sparse}" \
        --output_type TXT 2>/dev/null || true

    python3 "${COLMAP_STATS}" "${best_sparse}" \
        --out "${OUT_DIR}/stats.json" \
        --db "${db}" || \
        echo "  WARNING: quality gate failed — check ${OUT_DIR}/stats.json"
}

# ------------------------------------------------------------------
# Strategy B: Model merger
# ------------------------------------------------------------------
strategy_b() {
    echo "=== Strategy B: Model merger ==="

    local inputs=()
    for cam in pixel9 samsung_a15 gopro_max; do
        local m="${PER_CAM_DIR}/${cam}/sparse/0"
        if [[ -d "${m}" ]]; then
            inputs+=("${m}")
            echo "  Input: ${m}"
        else
            echo "  SKIP ${cam}: no sparse/0 found (run 06 first)"
        fi
    done

    [[ ${#inputs[@]} -ge 2 ]] || {
        echo "ERROR: need at least 2 per-cam models for merge" >&2
        exit 1
    }

    activate_env fselect

    local merged="${SPARSE_DIR}/merged"
    mkdir -p "${merged}"

    # colmap model_merger merges two models at a time; chain for 3
    local tmp1="${SPARSE_DIR}/tmp1"
    mkdir -p "${tmp1}"
    colmap model_merger \
        --input_path1 "${inputs[0]}" \
        --input_path2 "${inputs[1]}" \
        --output_path "${tmp1}"

    if [[ ${#inputs[@]} -ge 3 ]]; then
        colmap model_merger \
            --input_path1 "${tmp1}" \
            --input_path2 "${inputs[2]}" \
            --output_path "${merged}"
    else
        cp -r "${tmp1}"/* "${merged}/"
    fi

    colmap model_converter \
        --input_path "${merged}" \
        --output_path "${merged}" \
        --output_type TXT 2>/dev/null || true

    python3 "${COLMAP_STATS}" "${merged}" \
        --out "${OUT_DIR}/stats.json" || \
        echo "  WARNING: quality gate failed"
}

write_merge_strategy_doc

case "${STRATEGY}" in
    A) strategy_a ;;
    B) strategy_b ;;
    *) echo "ERROR: unknown strategy '${STRATEGY}'" >&2; exit 1 ;;
esac

echo ""
echo "=== Phase 07 complete (strategy=${STRATEGY}) ==="
if [[ -f "${OUT_DIR}/stats.json" ]]; then
    python3 - <<PYEOF
import json
d = json.load(open("${OUT_DIR}/stats.json"))
print(f"  registered: {d['registered_images']}/{d['total_images']} ({d['registered_pct']}%)")
print(f"  points3D:   {d['num_points3d']}")
print(f"  reproj err: {d['reproj_err_mean']}px")
gates = [k for k,v in d['gates'].items() if not v['passed']]
if gates:
    print(f"  FAILED gates: {gates}")
else:
    print("  All quality gates passed.")
PYEOF
fi
echo ""
echo "NEXT: Run 10_train.sh --trainer gsplat"
echo "      Inspect: cat ${OUT_DIR}/stats.json"

commit_phase "phase-07-colmap-merge" "strategy=${STRATEGY}"
