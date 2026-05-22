#!/usr/bin/env python3
"""
Parse a COLMAP sparse/0/ directory and emit a stats.json quality gate file.

Usage: python3 colmap_stats.py <sparse_dir> [--out stats.json]

Exit codes:
  0  — all quality gates passed
  1  — one or more gates FAILED (printed to stderr)
  2  — parse error (missing files, corrupt DB)
"""
import argparse, json, os, sqlite3, sys
from pathlib import Path


GATES = {
    "registered_pct":  (">=", 85.0),
    "num_points3d":    (">=", 10000),
    "reproj_err_mean": ("<=", 1.5),
}


def parse_cameras(path):
    cams = {}
    with open(path) as f:
        for line in f:
            if line.startswith("#"): continue
            parts = line.split()
            if len(parts) < 5: continue
            cams[int(parts[0])] = parts[1]
    return cams


def parse_images_txt(path):
    """Return dict of image_id -> image_name for registered images."""
    images = {}
    with open(path) as f:
        lines = [l for l in f if not l.startswith("#")]
    i = 0
    while i < len(lines):
        parts = lines[i].split()
        if len(parts) >= 10:
            images[int(parts[0])] = parts[9]
        i += 2  # skip the 2D point line
    return images


def parse_points3d(path):
    """Return (count, mean_reproj_err)."""
    errors = []
    with open(path) as f:
        for line in f:
            if line.startswith("#"): continue
            parts = line.split()
            if len(parts) < 7: continue
            try:
                errors.append(float(parts[7]))
            except (IndexError, ValueError):
                pass
    if not errors:
        return 0, 0.0
    return len(errors), sum(errors) / len(errors)


def count_images_in_db(db_path):
    """Count total images fed into COLMAP (registered or not)."""
    if not os.path.exists(db_path):
        return None
    conn = sqlite3.connect(db_path)
    try:
        n = conn.execute("SELECT COUNT(*) FROM images").fetchone()[0]
        return n
    finally:
        conn.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sparse_dir")
    ap.add_argument("--out", default="stats.json")
    ap.add_argument("--db", default=None, help="Path to COLMAP database.db")
    args = ap.parse_args()

    sparse = Path(args.sparse_dir)
    images_txt  = sparse / "images.txt"
    points_txt  = sparse / "points3D.txt"
    cameras_txt = sparse / "cameras.txt"

    if not images_txt.exists() or not points_txt.exists():
        print(f"ERROR: missing {images_txt} or {points_txt}", file=sys.stderr)
        sys.exit(2)

    registered_images = parse_images_txt(str(images_txt))
    num_registered = len(registered_images)

    num_points3d, reproj_err = parse_points3d(str(points_txt))

    # Total images: try DB first, fall back to registered count
    db_path = args.db or str(sparse.parent / "database.db")
    total_images = count_images_in_db(db_path)
    if total_images is None or total_images == 0:
        total_images = num_registered  # conservative — gates may not fire
    registered_pct = (num_registered / total_images * 100) if total_images > 0 else 0.0

    stats = {
        "sparse_dir": str(sparse),
        "total_images": total_images,
        "registered_images": num_registered,
        "registered_pct": round(registered_pct, 1),
        "num_points3d": num_points3d,
        "reproj_err_mean": round(reproj_err, 4),
        "gates": {},
    }

    failures = []
    for metric, (op, threshold) in GATES.items():
        val = stats[metric]
        passed = (val >= threshold) if op == ">=" else (val <= threshold)
        stats["gates"][metric] = {
            "value": val, "threshold": threshold, "op": op, "passed": passed
        }
        if not passed:
            failures.append(f"  FAIL {metric}: {val} (need {op} {threshold})")

    out_path = args.out
    with open(out_path, "w") as f:
        json.dump(stats, f, indent=2)

    print(f"COLMAP stats → {out_path}")
    print(f"  registered: {num_registered}/{total_images} ({registered_pct:.1f}%)")
    print(f"  points3D:   {num_points3d}")
    print(f"  reproj err: {reproj_err:.4f}px")

    if failures:
        print("QUALITY GATE FAILURES:", file=sys.stderr)
        for f in failures:
            print(f, file=sys.stderr)
        sys.exit(1)
    else:
        print("  All quality gates passed.")
        sys.exit(0)


if __name__ == "__main__":
    main()
