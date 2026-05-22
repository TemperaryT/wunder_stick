#!/usr/bin/env bash
# gsplat direct trainer.
# Calls gsplat's simple_trainer.py (must be fetched from GitHub — not bundled in pip install).
# Input: a COLMAP scene dir containing images/ and sparse/0/.
# Output: <exp_dir>/  (splat.ply + renders + metrics)
#
# Usage: called via 10_train.sh -- do not invoke directly.
# Direct usage:
#   ./gsplat_direct.sh --scene-dir <colmap_dir> --exp-dir <experiments/exp-NNN> [options]
#
# Options:
#   --scene-dir <path>    COLMAP scene dir (contains images/ + sparse/0/)
#   --exp-dir <path>      Output experiment directory
#   --cap-max <int>       Max gaussians (default 1000000; scale up if VRAM allows)
#   --steps <int>         Training steps (default 30000)
#   --strategy <mcmc|default>  Gaussian strategy (default: mcmc)
#   --fetch-trainer       Force re-download simple_trainer.py from gsplat GitHub
#
# Inspection after run:
#   ls <exp_dir>/          # should contain splat.ply (or .splat), metrics.json
#   cat <exp_dir>/metrics.json   # PSNR, SSIM, LPIPS
#   nvidia-smi             # check VRAM usage during training
# Expected VRAM: ~8-12GB for cap_max=1M. Reduce cap_max if OOM.
# Expected training time: ~15-30min on RTX 4090 for 30k steps.
# Success: PSNR > 25dB for per-cam, > 26.5dB for merged.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

SCENE_DIR=""
EXP_DIR=""
CAP_MAX=1000000
STEPS=30000
STRATEGY="mcmc"
FETCH_TRAINER=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scene-dir)     SCENE_DIR="$2"; shift ;;
        --exp-dir)       EXP_DIR="$2"; shift ;;
        --cap-max)       CAP_MAX="$2"; shift ;;
        --steps)         STEPS="$2"; shift ;;
        --strategy)      STRATEGY="$2"; shift ;;
        --fetch-trainer) FETCH_TRAINER=1 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

[[ -n "${SCENE_DIR}" ]] || { echo "ERROR: --scene-dir required" >&2; exit 1; }
[[ -n "${EXP_DIR}" ]]   || { echo "ERROR: --exp-dir required" >&2; exit 1; }
[[ -d "${SCENE_DIR}/sparse/0" ]] || { echo "ERROR: ${SCENE_DIR}/sparse/0 not found" >&2; exit 1; }
[[ -d "${SCENE_DIR}/images" ]]   || { echo "ERROR: ${SCENE_DIR}/images not found — create symlink or copy frames" >&2; exit 1; }

mkdir -p "${EXP_DIR}"

# ------------------------------------------------------------------
# Locate or fetch simple_trainer.py
# ------------------------------------------------------------------
TRAINER_CACHE="${HOME}/.cache/gsplat_examples"
TRAINER_SCRIPT="${TRAINER_CACHE}/simple_trainer.py"

if [[ "${FETCH_TRAINER}" -eq 1 || ! -f "${TRAINER_SCRIPT}" ]]; then
    echo "Fetching simple_trainer.py from gsplat GitHub examples..."
    mkdir -p "${TRAINER_CACHE}"
    # gsplat 1.4.x examples: use the tagged release branch
    curl -fsSL \
        "https://raw.githubusercontent.com/nerfstudio-project/gsplat/v1.4.0/examples/simple_trainer.py" \
        -o "${TRAINER_SCRIPT}" || {
        echo "ERROR: failed to download simple_trainer.py" >&2
        echo "  Try manually: cd ${TRAINER_CACHE} && wget https://github.com/nerfstudio-project/gsplat/raw/v1.4.0/examples/simple_trainer.py" >&2
        exit 1
    }
    echo "  Saved to ${TRAINER_SCRIPT}"
fi

# ------------------------------------------------------------------
# GPU check
# ------------------------------------------------------------------
echo "=== GPU status ==="
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || \
    echo "WARNING: nvidia-smi unavailable — GPU may not be accessible"

# ------------------------------------------------------------------
# Train
# ------------------------------------------------------------------
activate_env nerfstudio

echo ""
echo "=== gsplat direct trainer ==="
echo "  scene:    ${SCENE_DIR}"
echo "  exp:      ${EXP_DIR}"
echo "  strategy: ${STRATEGY}"
echo "  cap_max:  ${CAP_MAX}"
echo "  steps:    ${STEPS}"
echo ""

# tyro CLI: strategy is selected positionally, nested params via --strategy.cap_max
python3 "${TRAINER_SCRIPT}" "${STRATEGY}" \
    --data_dir "${SCENE_DIR}" \
    --result_dir "${EXP_DIR}" \
    --strategy.cap_max "${CAP_MAX}" \
    --max_steps "${STEPS}" \
    --antialiased \
    2>&1 | tee "${EXP_DIR}/train.log"

# ------------------------------------------------------------------
# Locate output PLY
# ------------------------------------------------------------------
PLY=$(find "${EXP_DIR}" -name "*.ply" 2>/dev/null | head -1)
if [[ -n "${PLY}" ]]; then
    echo ""
    echo "Output PLY: ${PLY}"
    # Verify SH coefficient format (not RGB)
    python3 - <<PYEOF
import sys
ply = "${PLY}"
with open(ply, "rb") as f:
    header = f.read(4096).decode("latin-1")
if "f_dc_0" in header:
    print("  PLY format: SH coefficients confirmed (f_dc_* present) — correct")
elif "red" in header.lower():
    print("  WARNING: PLY uses RGB format (not SH). SuperSplat will show black. Re-export needed.", file=sys.stderr)
else:
    print("  PLY format: unknown — inspect header manually")
PYEOF
else
    echo "WARNING: no .ply found in ${EXP_DIR}" >&2
fi

echo ""
echo "=== Training complete ==="
echo "  Log: ${EXP_DIR}/train.log"
echo "  Inspect metrics: cat ${EXP_DIR}/train.log | grep -E 'PSNR|SSIM|LPIPS'"
echo "  Open in SuperSplat: https://playcanvas.com/supersplat/editor (drag PLY)"
