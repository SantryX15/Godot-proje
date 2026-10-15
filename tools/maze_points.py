"""maze_grid.txt.json'dan duvara değmeyen nokta seçer + minimap PNG'si üretir.
Kullanım: python maze_points.py <grid.json> <minimap.png>
"""
import sys, json, math, zlib, struct

g = json.load(open(sys.argv[1]))
xs, zs, grid = g["xs"], g["zs"], g["grid"]
H, W = len(grid), len(grid[0])

def clear(r, c, rad=1):
    for dr in range(-rad, rad + 1):
        for dc in range(-rad, rad + 1):
            rr, cc = r + dr, c + dc
            if not (0 <= rr < H and 0 <= cc < W) or grid[rr][cc]:
                return False
    # labirent dışı bant (ilk/son satır) sayılmasın
    return 1 < r < H - 2 and 1 < c < W - 2

cells = [(r, c) for r in range(H) for c in range(W) if clear(r, c)]

def pick(target, n, min_sep):
    tx, tz = target
    cand = sorted(cells, key=lambda rc: (xs[rc[1]] - tx) ** 2 + (zs[rc[0]] - tz) ** 2)
    out = []
    for r, c in cand:
        p = (xs[c], zs[r])
        if all(math.dist(p, q) >= min_sep for q in out):
            out.append(p)
        if len(out) == n:
            break
    return out

res = {
    "spawns": {t: pick(p, 5, 2.0) for t, p in
               {0: (-58, -40), 1: (58, -40), 2: (-58, 40), 3: (58, 40)}.items()},
    "doors": [pick(p, 1, 0)[0] for p in [(-44.6, -34.5), (44.6, -34.5), (-44.6, 34.5), (44.6, 34.5)]],
    "cards": pick((0, 0), 6, 4.0),
}
for k, v in res.items():
    print(k, v)

# Minimap: duvar = beyaz opak, boş = şeffaf (1 px = 1 m)
raw = b"".join(b"\x00" + b"".join(b"\xff\xff\xff\xff" if grid[r][c] else b"\x00\x00\x00\x00" for c in range(W)) for r in range(H))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) \
      + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(sys.argv[2], "wb").write(png)
print("minimap", W, "x", H, "extent x", xs[0] - 0.5, xs[-1] + 0.5, "z", zs[0] - 0.5, zs[-1] + 0.5)
