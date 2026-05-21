# LiDAR Alignment (Hovermap → Splat) — PLACEHOLDER

## Status

**Deferred.** The Emerson Hovermap scan from the 2026-05-20 capture has not yet
been uploaded. This doc captures the plan so a fresh session can pick it up
without re-litigating the approach.

When the scan arrives:

1. Drop the `.e57` (or `.las`) into `00_raw/lidar/` and update
   `00_raw/checksums.sha256`.
2. Update `00_raw/camera_manifest.json` with the LiDAR file metadata.
3. Re-read this doc and proceed with the chosen path below.

## Goal

Produce a 4×4 transform `T_splat→lidar` such that applying it to the splat brings
it into the LiDAR coordinate frame (or vice versa). Persist as
`08_lidar/registration.json`.

Success criterion: on flat surfaces (floor slabs, large walls), splat points
within **5cm** of the LiDAR surface after transformation.

## Approach selection

Two paths. Try in order. Move to the next only if the previous fails or produces
a bad result.

### Path A — Unreal Reality Scan (desktop) — TRY FIRST

The operator has Unreal Reality Scan installed on Windows main. Reality Scan
(formerly RealityCapture) supports importing both a 3DGS PLY and a LiDAR point
cloud, and can do guided alignment between them. If it works, it skips the entire
manual coarse + fine alignment dance below.

Procedure (rough — refine after first attempt):

1. Transfer to Windows main:
   - `results/winning_splat.ply` (or the best per-cam if no merge yet)
   - `00_raw/lidar/<scan>.e57`
2. Open Reality Scan on Windows main.
3. New project → import both files as separate components.
4. Use the alignment tool to pick 4-6 corresponding points between splat and scan
   (corners, fixtures, anything geometric and unambiguous).
5. Run Reality Scan's alignment.
6. Export the alignment transform (Reality Scan format → convert to 4×4 JSON).
7. Copy `registration.json` back to WSL `08_lidar/`.

**Stop here if Reality Scan produces a < 5cm error.** Skip Path B.

### Path B — CloudCompare + Open3D (fallback)

If Reality Scan can't handle one of the two formats or the alignment quality is
unacceptable.

#### B.1 Coarse alignment in CloudCompare (manual)

1. Open both clouds (`splat.ply` and `scan.e57`) in CloudCompare (Linux or
   Windows — either works).
2. Use "Align (point pairs picking)" — pick 4-6 corresponding points between the
   two clouds. Industrial scenes usually have unambiguous corners or fixtures.
3. Apply transform. Save the transformed splat as `08_lidar/splat_coarse.ply`.
4. Save the 4×4 transform CloudCompare reports as `08_lidar/coarse_transform.txt`.

#### B.2 Fine alignment with Open3D ICP

Script (to be written as `scripts/08_lidar_register.sh`):

```python
import open3d as o3d, numpy as np, json
splat = o3d.io.read_point_cloud("08_lidar/splat_coarse.ply")
lidar = o3d.io.read_point_cloud("00_raw/lidar/scan.e57")
# Downsample for speed, then ICP point-to-plane
voxel = 0.05  # 5cm
splat_d = splat.voxel_down_sample(voxel)
lidar_d = lidar.voxel_down_sample(voxel)
splat_d.estimate_normals(); lidar_d.estimate_normals()
reg = o3d.pipelines.registration.registration_icp(
    splat_d, lidar_d, max_correspondence_distance=0.20,
    estimation_method=o3d.pipelines.registration.TransformationEstimationPointToPlane(),
)
print("fitness:", reg.fitness, "inlier_rmse:", reg.inlier_rmse)
# Compose with coarse transform from CloudCompare
T_coarse = np.loadtxt("08_lidar/coarse_transform.txt")
T_final = reg.transformation @ T_coarse
json.dump({"transform_4x4": T_final.tolist(),
           "rmse_meters": float(reg.inlier_rmse),
           "fitness": float(reg.fitness)},
          open("08_lidar/registration.json", "w"), indent=2)
```

Success: `inlier_rmse < 0.05` (5cm). If higher, re-pick coarse points or
investigate splat scale (raw 3DGS output is unitless; the LiDAR is in meters).

## Things to watch out for

- **Scale.** 3DGS output is in arbitrary units. The CloudCompare alignment will
  recover scale via the point-pair correspondences — but if your point pairs are
  too close together, scale recovery is unstable. Pick at least one pair across
  the largest dimension of the scene.
- **Z-up vs Y-up.** COLMAP/3DGS conventions differ from LiDAR vendor conventions.
  Don't assume axis alignment — the coarse pick will sort it out.
- **Coordinate frame ambiguity.** Document which way `registration.json` goes:
  `splat → lidar` (what we want) vs `lidar → splat`. Pick one and stick with it.

## See also

- `00_pipeline_overview.md` — Phase 08 placement in the overall flow
- `00_raw/camera_manifest.json` — will gain a `lidar:` section when scan arrives
- `scripts/08_lidar_register.sh` — currently a placeholder, exits 0 with guidance
