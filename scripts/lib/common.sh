#!/usr/bin/env bash
# Shared helpers for all wunder_stick scripts.
set -euo pipefail

WUNDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONDA_BASE="${CONDA_BASE:-/home/ops/miniforge3}"

activate_env() {
    local env_name="$1"
    # shellcheck disable=SC1091
    source "${CONDA_BASE}/etc/profile.d/conda.sh"
    conda activate "${env_name}"
}

# Safe frame count — never fails on empty dir
count_frames() {
    local dir="$1"
    find "${dir}" -maxdepth 1 -name "*.jpg" -o -name "*.png" 2>/dev/null | wc -l || echo 0
}

# Require a directory to exist and be non-empty
require_frames() {
    local dir="$1" label="${2:-frames}"
    local n
    n=$(count_frames "${dir}")
    if [[ "${n}" -eq 0 ]]; then
        echo "ERROR: No frames found in ${dir} (${label})" >&2
        exit 1
    fi
    echo "Found ${n} ${label} in ${dir}"
}

# Log a phase completion to LOG.md
log_phase() {
    local phase_name="$1" notes="${2:-}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M')
    echo "- ${timestamp} ${phase_name} complete. ${notes}" >> "${WUNDER_ROOT}/LOG.md"
}

# Abort if 00_raw/ checksum verification fails
verify_checksums() {
    echo "Verifying raw checksums..."
    pushd "${WUNDER_ROOT}" > /dev/null
    sha256sum -c 00_raw/checksums.sha256
    popd > /dev/null
    echo "Checksums OK."
}
