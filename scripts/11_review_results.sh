#!/usr/bin/env bash
# Phase 11: Post-training results review.
# Reads an experiment directory, parses metrics from train.log, updates README + CSV.
#
# Usage: ./11_review_results.sh --exp <experiments/exp-NNN-desc> [--promote]
#
# --promote: symlinks results/winning_splat.ply to this experiment's PLY.
#
# Inspection:
#   cat results/metrics_summary.csv               # all experiments
#   cat <exp_dir>/README.md                       # filled-in metrics + verdict
#   cat results/README.md                         # winning splat notes
#
# PLY format check: must use SH coefficients (f_dc_*, f_rest_*), NOT RGB.
# Open in SuperSplat: https://playcanvas.com/supersplat/editor  (drag and drop PLY)
# "Black on load" in SuperSplat = RGB format. gsplat writes SH natively — should be fine.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

EXP_DIR=""
PROMOTE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --exp)     EXP_DIR="$2"; shift ;;
        --promote) PROMOTE=1 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

[[ -n "${EXP_DIR}" ]] || { echo "ERROR: --exp required" >&2; exit 1; }
[[ -d "${EXP_DIR}" ]] || { echo "ERROR: ${EXP_DIR} not found" >&2; exit 1; }

LOG="${EXP_DIR}/train.log"
CSV="${ROOT}/results/metrics_summary.csv"
README="${EXP_DIR}/README.md"
EXP_ID=$(basename "${EXP_DIR}" | grep -oP '^exp-\K\d+' || echo "?")

mkdir -p "${ROOT}/results"

# ------------------------------------------------------------------
# Parse metrics from train.log
# ------------------------------------------------------------------
echo "=== Reviewing ${EXP_DIR} ==="

PSNR="" SSIM="" LPIPS="" GAUSSIANS=""
if [[ -f "${LOG}" ]]; then
    PSNR=$(grep -oP 'PSNR[:\s=]+\K[\d.]+' "${LOG}" | tail -1 || true)
    SSIM=$(grep -oP 'SSIM[:\s=]+\K[\d.]+' "${LOG}" | tail -1 || true)
    LPIPS=$(grep -oP 'LPIPS[:\s=]+\K[\d.]+' "${LOG}" | tail -1 || true)
    GAUSSIANS=$(grep -oP 'num_gaussians[:\s=]+\K[\d]+' "${LOG}" | tail -1 || true)
fi

PLY=$(find "${EXP_DIR}" -name "*.ply" 2>/dev/null | head -1)
PLY_MB=""
[[ -n "${PLY}" ]] && PLY_MB=$(du -m "${PLY}" | cut -f1)

echo "  PSNR:      ${PSNR:-unknown}"
echo "  SSIM:      ${SSIM:-unknown}"
echo "  LPIPS:     ${LPIPS:-unknown}"
echo "  Gaussians: ${GAUSSIANS:-unknown}"
echo "  PLY:       ${PLY:-none} (${PLY_MB:-?}MB)"

# PLY format check
if [[ -n "${PLY}" ]]; then
    python3 - <<PYEOF
with open("${PLY}", "rb") as f:
    header = f.read(4096).decode("latin-1")
if "f_dc_0" in header:
    print("  PLY format: SH coefficients (f_dc_*) — correct")
elif "red" in header.lower():
    print("  WARNING: PLY format is RGB — will appear black in SuperSplat")
else:
    print("  PLY format: unrecognized — check header manually")
PYEOF
fi

# ------------------------------------------------------------------
# Update README.md metrics table
# ------------------------------------------------------------------
python3 - <<PYEOF
import re

psnr      = "${PSNR}"
ssim      = "${SSIM}"
lpips     = "${LPIPS}"
gaussians = "${GAUSSIANS}"
ply_mb    = "${PLY_MB}"

readme = "${README}"
with open(readme) as f:
    content = f.read()

def replace_metric(text, label, value):
    if not value:
        return text
    return re.sub(
        rf'(\| {label}\s*\|)\s*TBD\s*\|',
        rf'\1 {value} |',
        text
    )

content = replace_metric(content, "PSNR", psnr)
content = replace_metric(content, "SSIM", ssim)
content = replace_metric(content, "LPIPS", lpips)
content = replace_metric(content, "Gaussians", gaussians)
content = replace_metric(content, "PLY size", f"{ply_mb}MB" if ply_mb else "")

with open(readme, "w") as f:
    f.write(content)
print("  README.md updated")
PYEOF

# ------------------------------------------------------------------
# Update metrics_summary.csv
# ------------------------------------------------------------------
if [[ -f "${CSV}" ]]; then
    python3 - <<PYEOF
import csv, io, sys

csv_path  = "${CSV}"
exp_id    = "${EXP_ID}"
psnr      = "${PSNR}"
ssim      = "${SSIM}"
lpips     = "${LPIPS}"
gaussians = "${GAUSSIANS}"
ply_mb    = "${PLY_MB}"

with open(csv_path) as f:
    rows = list(csv.DictReader(f))
fieldnames = rows[0].keys() if rows else []

updated = False
for row in rows:
    if row.get("exp_id") == exp_id:
        if psnr:      row["psnr"]      = psnr
        if ssim:      row["ssim"]      = ssim
        if lpips:     row["lpips"]     = lpips
        if gaussians: row["gaussians"] = gaussians
        if ply_mb:    row["ply_mb"]    = ply_mb
        updated = True

if not updated:
    print(f"  exp_id {exp_id} not found in CSV — no update", file=sys.stderr)
else:
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"  {csv_path} updated")
PYEOF
fi

# ------------------------------------------------------------------
# Promote to winning splat
# ------------------------------------------------------------------
if [[ "${PROMOTE}" -eq 1 && -n "${PLY}" ]]; then
    WINNING="${ROOT}/results/winning_splat.ply"
    ln -sf "$(realpath "${PLY}")" "${WINNING}"
    echo "  Promoted: ${WINNING} → ${PLY}"
    cat >> "${ROOT}/results/README.md" 2>/dev/null <<EOF || \
    echo "## Winning splat" > "${ROOT}/results/README.md" && \
    echo "- exp: ${EXP_DIR}" >> "${ROOT}/results/README.md" && \
    echo "- PLY: ${PLY}" >> "${ROOT}/results/README.md"
- $(date '+%Y-%m-%d'): promoted exp-${EXP_ID} (PSNR=${PSNR})
EOF
fi

echo ""
echo "=== Review complete ==="
echo "  README: ${README}"
echo "  CSV:    ${CSV}"
