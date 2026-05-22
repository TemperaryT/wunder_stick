#!/usr/bin/env bash
# Phase 09/10: Training dispatcher.
# Creates an experiment directory, writes README.md template, then delegates to a trainer backend.
#
# Usage: ./10_train.sh --trainer <gsplat|lichtfeld>
#                      --scene-dir <colmap_scene_dir>
#                      [--exp-id <NNN>]          # auto-assigned if omitted
#                      [--desc <short-description>]
#                      [--cap-max <int>]          # gsplat: gaussian cap (default 1M)
#                      [--steps <int>]            # gsplat: training steps (default 30k)
#                      [--dry-run]               # create exp dir + README only, no training
#
# Scene dir must contain:
#   images/     (flat dir of all frames, cam-prefixed for merged)
#   sparse/0/   (COLMAP sparse reconstruction in TXT format)
#
# Inspection after run:
#   cat experiments/exp-NNN-<desc>/README.md       # inputs, config, metrics, verdict
#   cat results/metrics_summary.csv                # all experiments at a glance
#
# For manual Postshot comparison: see docs/08_postshot_protocol.md

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

TRAINER=""
SCENE_DIR=""
EXP_ID=""
DESC=""
CAP_MAX=1000000
STEPS=30000
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --trainer)   TRAINER="$2"; shift ;;
        --scene-dir) SCENE_DIR="$2"; shift ;;
        --exp-id)    EXP_ID="$2"; shift ;;
        --desc)      DESC="$2"; shift ;;
        --cap-max)   CAP_MAX="$2"; shift ;;
        --steps)     STEPS="$2"; shift ;;
        --dry-run)   DRY_RUN=1 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

[[ -n "${TRAINER}" ]]   || { echo "ERROR: --trainer required (gsplat|lichtfeld)" >&2; exit 1; }
[[ -n "${SCENE_DIR}" ]] || { echo "ERROR: --scene-dir required" >&2; exit 1; }

# Auto-assign experiment ID
if [[ -z "${EXP_ID}" ]]; then
    last=$(ls -d "${ROOT}/experiments"/exp-* 2>/dev/null | sort | tail -1 | grep -oP '(?<=exp-)\d+' || echo "000")
    EXP_ID=$(printf "%03d" $(( 10#${last} + 1 )))
fi

[[ -n "${DESC}" ]] || DESC="${TRAINER}-$(basename "${SCENE_DIR}")"
EXP_NAME="exp-${EXP_ID}-${DESC//[^a-zA-Z0-9_-]/-}"
EXP_DIR="${ROOT}/experiments/${EXP_NAME}"

mkdir -p "${EXP_DIR}" "${ROOT}/results"

# ------------------------------------------------------------------
# Write README template
# ------------------------------------------------------------------
N_FRAMES=$(find "${SCENE_DIR}/images" -name "*.jpg" -o -name "*.png" 2>/dev/null | wc -l || echo "?")
cat > "${EXP_DIR}/README.md" <<EOF
# ${EXP_NAME}

## Inputs
- Scene dir: \`${SCENE_DIR}\`
- Frames: ${N_FRAMES}
- Trainer: ${TRAINER}

## Config
- cap_max: ${CAP_MAX}
- steps: ${STEPS}

## Run
- Date: $(date '+%Y-%m-%d %H:%M')
- Status: $([ "${DRY_RUN}" -eq 1 ] && echo "DRY RUN" || echo "training")

## Metrics
| Metric | Value |
|--------|-------|
| PSNR   | TBD   |
| SSIM   | TBD   |
| LPIPS  | TBD   |
| Gaussians | TBD |
| PLY size | TBD |
| Wall time | TBD |

## Verdict
TBD

## Notes
EOF

echo "=== Experiment: ${EXP_NAME} ==="
echo "  exp_dir: ${EXP_DIR}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  DRY RUN — no training. Edit ${EXP_DIR}/README.md then re-run without --dry-run."
    exit 0
fi

# ------------------------------------------------------------------
# Validate scene dir has images/ symlink
# ------------------------------------------------------------------
if [[ ! -d "${SCENE_DIR}/images" ]]; then
    echo "ERROR: ${SCENE_DIR}/images not found." >&2
    echo "  For per-cam models, create symlink: ln -s <masked_or_filtered_dir> ${SCENE_DIR}/images" >&2
    echo "  For merged, 07_colmap_merge.sh creates images/ automatically." >&2
    exit 1
fi

# ------------------------------------------------------------------
# Dispatch to trainer backend
# ------------------------------------------------------------------
START_TS=$(date +%s)

case "${TRAINER}" in
    gsplat)
        "${SCRIPT_DIR}/trainers/gsplat_direct.sh" \
            --scene-dir "${SCENE_DIR}" \
            --exp-dir "${EXP_DIR}" \
            --cap-max "${CAP_MAX}" \
            --steps "${STEPS}"
        ;;
    lichtfeld)
        echo "ERROR: lichtfeld trainer not yet implemented. See scripts/trainers/lichtfeld.sh stub." >&2
        exit 1
        ;;
    *)
        echo "ERROR: unknown trainer '${TRAINER}'" >&2
        exit 1
        ;;
esac

WALL_SEC=$(( $(date +%s) - START_TS ))
WALL_MIN=$(( WALL_SEC / 60 ))

# ------------------------------------------------------------------
# Append to metrics_summary.csv
# ------------------------------------------------------------------
CSV="${ROOT}/results/metrics_summary.csv"
if [[ ! -f "${CSV}" ]]; then
    echo "exp_id,trainer,source,n_frames,psnr,ssim,lpips,gaussians,ply_mb,wall_min,verdict,notes" > "${CSV}"
fi

PLY=$(find "${EXP_DIR}" -name "*.ply" 2>/dev/null | head -1)
PLY_MB=""
[[ -n "${PLY}" ]] && PLY_MB=$(du -m "${PLY}" | cut -f1)

# Extract PSNR from log if present
PSNR=$(grep -oP 'PSNR[:\s=]+\K[\d.]+' "${EXP_DIR}/train.log" 2>/dev/null | tail -1 || echo "")

echo "${EXP_ID},${TRAINER},$(basename "${SCENE_DIR}"),${N_FRAMES},${PSNR},,,,${PLY_MB},${WALL_MIN},," >> "${CSV}"

echo ""
echo "=== Phase 10 complete ==="
echo "  Experiment: ${EXP_DIR}"
echo "  Wall time:  ${WALL_MIN}min"
echo "  CSV row:    ${CSV}"
echo ""
echo "NEXT: Run 11_review_results.sh to finalize metrics in README and CSV"
