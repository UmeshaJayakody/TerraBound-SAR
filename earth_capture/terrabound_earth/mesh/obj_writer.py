"""Writes a scene as a Wavefront OBJ the MATLAB pipeline reads: one "usemtl" block per material."""
from __future__ import annotations

from pathlib import Path

import numpy as np

from .materials import mtl_text


def write_obj(path: Path, vertices: np.ndarray, faces: np.ndarray, face_material: np.ndarray, names: list[str],
              header: list[str]) -> dict:
    """vertices: n x 3 in the scene's axes (x east, y up, z south), metres. faces: m x 3, 0-based.
    face_material: index into names for each face. Writes path and path.mtl; returns counts."""
    path = Path(path)
    order = np.argsort(face_material, kind="stable")
    faces = faces[order]
    mats = face_material[order]
    used = [names[i] for i in np.unique(mats)]
    mtl = path.with_suffix(".mtl")
    mtl.write_text(mtl_text(used), encoding="utf-8")

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for line in header:
            f.write(f"# {line}\n")
        f.write(f"mtllib {mtl.name}\n")
        np.savetxt(f, vertices, fmt="v %.3f %.3f %.3f")
        bounds = np.flatnonzero(np.diff(mats)) + 1
        starts = np.concatenate([[0], bounds])
        stops = np.concatenate([bounds, [len(mats)]])
        for s, e in zip(starts, stops):
            f.write(f"usemtl {names[mats[s]]}\n")
            np.savetxt(f, faces[s:e] + 1, fmt="f %d %d %d")
    counts = {names[i]: int(np.sum(mats == i)) for i in np.unique(mats)}
    return {"vertices": int(len(vertices)), "triangles": int(len(faces)), "materials": counts}
