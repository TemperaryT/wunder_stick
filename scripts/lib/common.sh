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

# Abort if a required python module isn't importable in the current env.
require_python_module() {
    local module="$1" install_hint="${2:-pip install ${module}}"
    if ! python3 -c "import ${module}" 2>/dev/null; then
        echo "ERROR: python module '${module}' is required but not importable." >&2
        echo "  Hint: ${install_hint}" >&2
        echo "  Current python: $(command -v python3)" >&2
        exit 1
    fi
}

# Halt-resilience: stage tracked metadata, commit phase, tag.
# Idempotent — if phase tag already exists, no-op (returns success).
# Untracked data outputs (00_raw/, 01_edits/, frames, ply) are excluded by .gitignore.
#
# Usage: commit_phase "phase-NN-short-name" "human-readable notes"
commit_phase() {
    local phase_name="$1" notes="${2:-}"
    local tag="${phase_name}-complete"

    pushd "${WUNDER_ROOT}" > /dev/null

    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "WARNING: not in a git repo — skipping commit_phase." >&2
        popd > /dev/null
        return 0
    fi

    if git rev-parse "refs/tags/${tag}" > /dev/null 2>&1; then
        echo "commit_phase: tag '${tag}' already exists — phase already recorded, skipping."
        popd > /dev/null
        return 0
    fi

    log_phase "${phase_name}" "${notes}"

    git add NOW.md LOG.md 2>/dev/null || true
    for f in 00_raw/checksums.sha256 00_raw/camera_manifest.json \
             01_edits/sync_offsets.json 02_360_extracted/conversion_notes.md \
             06_colmap_per_cam/*/stats.json 07_colmap_merged/stats.json \
             07_colmap_merged/merge_strategy.md; do
        [[ -e "${f}" ]] && git add "${f}" 2>/dev/null || true
    done

    if git diff --cached --quiet; then
        echo "commit_phase: nothing staged to commit; tagging ${tag} on HEAD."
    else
        local msg="phase: ${phase_name}"
        [[ -n "${notes}" ]] && msg="${msg} — ${notes}"
        git commit -m "${msg}" >&2
    fi

    git tag -a "${tag}" -m "${notes:-${phase_name}}"
    echo "commit_phase: tagged ${tag}."

    popd > /dev/null
}
