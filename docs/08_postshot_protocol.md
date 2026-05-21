# Postshot Protocol (Manual Comparison Tool)

## Status

Postshot is **not** part of the automated pipeline. It is used as a manual
blackbox comparison reference on Windows main. The operator has a paid Postshot
plan that exposes some CLI capability — full scripting feasibility is **not yet
confirmed** and is deferred to a future investigation session on Windows main.

Until that CLI investigation is complete, treat Postshot output as qualitative
("does the splat look right?"), not a measurement input to `metrics_summary.csv`.

## When to use it

- **Per-camera sanity check.** After Phase 04 (filtered frames) is done for a
  given camera, drop that camera's frames into Postshot and run with defaults.
  If Postshot can't produce a recognizable splat from a camera's frames in isolation,
  that camera will probably not contribute to a good merged result either.
- **Blackbox quality floor.** When a `gsplat direct` result looks suspiciously bad,
  run the same input through Postshot. If Postshot also looks bad, the problem is
  in the upstream COLMAP / frames, not the trainer.
- **Cross-check after unexpected gsplat result.** Same idea but for the merged scene.

## Manual procedure

### 1. Prepare the input on WSL

Decide what you're training on:

```bash
# Per-cam (recommended for first use):
INPUT_DIR=05_masked/pixel9         # or samsung_a15 / gopro_max
EXP_ID=postshot-percam-pixel9-001

# Or the merged scene:
INPUT_DIR=07_colmap_merged         # contains images/ + sparse/0/
EXP_ID=postshot-merged-001

mkdir -p experiments/${EXP_ID}
```

### 2. Transfer to Windows main

Via Tailscale (assumes `main` is your Tailscale node name; adjust if different):

```bash
rsync -aP ${INPUT_DIR}/ main:/c/Users/<user>/Desktop/wunder_stick/${EXP_ID}/
# also send the COLMAP sparse model if available (Postshot can import it as a prior):
[ -d 06_colmap_per_cam/<cam>/sparse ] && \
    rsync -aP 06_colmap_per_cam/<cam>/sparse/ main:/c/Users/<user>/Desktop/wunder_stick/${EXP_ID}/sparse/
```

### 3. Run Postshot on Windows main (GUI)

1. Launch Postshot.
2. New project → "Import Images" → point at the transferred folder.
3. If a COLMAP `sparse/` was transferred, "Import as Camera Calibration" using it
   (this skips Postshot's own SfM and gives a fairer comparison vs `gsplat direct`).
4. Training preset: **default** for first run. Note the exact preset name and any
   non-default values in step 5.
5. Run training to completion. Note wall-clock minutes.
6. Export PLY (SH coefficient format if the export dialog offers a choice — needed
   for SuperSplat visualization).

### 4. Copy results back to WSL

```bash
rsync -aP main:/c/Users/<user>/Desktop/wunder_stick/${EXP_ID}/exports/ \
    experiments/${EXP_ID}/postshot_exports/
ln -sf postshot_exports/splat.ply experiments/${EXP_ID}/splat.ply
```

### 5. Document in the experiment README

```bash
cat > experiments/${EXP_ID}/README.md <<EOF
# ${EXP_ID}

## Hypothesis
(why this comparison)

## Trainer
Postshot (manual GUI run on Windows main)

## Postshot version
(read from Postshot's About dialog)

## Inputs
- Source dir: ${INPUT_DIR}
- N frames: $(ls ${INPUT_DIR}/*.jpg 2>/dev/null | wc -l)
- COLMAP prior imported: (yes / no)

## Config
- Preset: default
- Non-default settings: (none / list)

## Metrics
- PSNR: (Postshot final viewer reading)
- Wall-clock minutes: ...
- Output PLY size: $(du -h experiments/${EXP_ID}/splat.ply | cut -f1)
- Gaussian count: (read from PLY header)

## Visual notes
(open in SuperSplat — describe what looks good/bad)

## Verdict
(promote / archive / re-run with what change)
EOF
```

### 6. Optional: append to metrics_summary.csv

Only if you took real PSNR/SSIM readings from Postshot's viewer. Otherwise leave
the row out — partial metrics pollute the comparison table.

## CLI investigation (deferred to Windows-main session)

The paid Postshot plan reportedly exposes some command-line capability. We do not
know:

- Whether it supports a fully headless training run
- Whether it can emit machine-readable metrics (JSON, CSV)
- Whether it can take a COLMAP sparse model as input non-interactively
- Whether outputs include SH-coefficient PLYs natively

If the CLI is viable, we add `scripts/trainers/postshot.sh` and Postshot graduates
from "manual reference" to "automated comparison backend." Until then, keep this
doc as the procedure of record.

## See also

- `07_trainer_comparison.md` (TBD) — once we have results from gsplat + Postshot + Lichtfeld
- `02_runbook.md` Phase 09 — `10_train.sh --trainer gsplat` (the automated path)
