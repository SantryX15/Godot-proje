"""Maze.obj -> Maze_walls.obj: sadece 'maze' objesi, ortalanmış + ölçeklenmiş, düz normaller.
Ayrıca duvar doluluk haritasını (ASCII) ve JSON'u yazar.
Kullanım: python maze_convert.py <src.obj> <dst.obj> <grid.txt>
"""
import sys, math, json

SXZ = 0.5          # yatay ölçek
TARGET_H = 3.0     # hedef duvar yüksekliği (m)

src, dst, grid_path = sys.argv[1], sys.argv[2], sys.argv[3]

verts, uvs, faces = [], [], []   # global indeksler (1-based)
cur = None
for line in open(src, encoding="utf-8", errors="ignore"):
    if line.startswith("# object"):
        cur = line.split()[-1]
    elif line.startswith("v "):
        verts.append([float(x) for x in line.split()[1:4]])
    elif line.startswith("vt "):
        uvs.append([float(x) for x in line.split()[1:3]])
    elif line.startswith("f ") and cur == "maze":
        f = []
        for tok in line.split()[1:]:
            parts = tok.split("/")
            f.append((int(parts[0]), int(parts[1]) if len(parts) > 1 and parts[1] else 0))
        faces.append(f)

used_v = sorted({vi for f in faces for vi, _ in f})
used_t = sorted({ti for f in faces for _, ti in f if ti})
mx = [verts[i - 1] for i in used_v]
minx, maxx = min(v[0] for v in mx), max(v[0] for v in mx)
miny, maxy = min(v[1] for v in mx), max(v[1] for v in mx)
minz, maxz = min(v[2] for v in mx), max(v[2] for v in mx)
cx, cz = (minx + maxx) / 2, (minz + maxz) / 2
sy = TARGET_H / (maxy - miny)

def tf(v):
    return ((v[0] - cx) * SXZ, (v[1] - miny) * sy, (v[2] - cz) * SXZ)

vmap = {old: i + 1 for i, old in enumerate(used_v)}
tmap = {old: i + 1 for i, old in enumerate(used_t)}
tv = {old: tf(verts[old - 1]) for old in used_v}

out = ["# Maze.obj'den üretildi (maze_convert.py): ortalanmış, XZ x%.2f, Y -> %.1fm, düz normaller" % (SXZ, TARGET_H), "o MazeWalls"]
for old in used_v:
    x, y, z = tv[old]
    out.append("v %.4f %.4f %.4f" % (x, y, z))
for old in used_t:
    out.append("vt %.4f %.4f" % tuple(uvs[old - 1]))

normals = []
for f in faces:
    # Newell yöntemi — n-gon için sağlam yüz normali
    nx = ny = nz = 0.0
    pts = [tv[vi] for vi, _ in f]
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
    l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    normals.append((nx / l, ny / l, nz / l))
for n in normals:
    out.append("vn %.4f %.4f %.4f" % n)
out.append("s off")
for fi, f in enumerate(faces):
    toks = []
    for vi, ti in f:
        toks.append("%d/%s/%d" % (vmap[vi], str(tmap[ti]) if ti else "", fi + 1))
    out.append("f " + " ".join(toks))
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")

# ── Doluluk haritası: üst yüzlerin (tüm köşeler tepede) XZ izdüşümü ──
top_y = TARGET_H * 0.9
tops = [[(tv[vi][0], tv[vi][2]) for vi, _ in f] for f in faces if all(tv[vi][1] > top_y for vi, _ in f)]

def inside(px, pz, poly):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]; xj, zj = poly[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / (zj - zi + 1e-12) + xi:
            c = not c
        j = i
    return c

hx, hz = (maxx - minx) * SXZ / 2, (maxz - minz) * SXZ / 2
RES = 1.0
xs = [(-math.ceil(hx) + 0.5) + i * RES for i in range(int(2 * math.ceil(hx) / RES))]
zs = [(-math.ceil(hz) + 0.5) + i * RES for i in range(int(2 * math.ceil(hz) / RES))]
grid = [[any(inside(x, z, p) for p in tops) for x in xs] for z in zs]
lines = ["# satır=z (%.1f..%.1f), sütun=x (%.1f..%.1f), RES=%.1f  #=duvar" % (zs[0], zs[-1], xs[0], xs[-1], RES)]
for zi, row in enumerate(grid):
    lines.append("%6.1f " % zs[zi] + "".join("#" if c else "." for c in row))
open(grid_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
json.dump({"xs": xs, "zs": zs, "grid": grid}, open(grid_path + ".json", "w"))

print("faces", len(faces), "verts", len(used_v), "top faces", len(tops))
print("half extents x=%.2f z=%.2f height=%.2f" % (hx, hz, TARGET_H))
print("center offset (orijinal) cx=%.3f cz=%.3f sy=%.4f" % (cx, cz, sy))
