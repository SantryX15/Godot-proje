"""Labirent ızgarasından duvar-üstü lamba noktaları seçer (Map.tscn → WallLamps/Lamp* Marker3D).
Nokta = koridora bakan düz duvar yüzü (duvar hücresi, bir yanında ≥2 m boş koridor, iki yanı da duvar).
Marker'ın -Z'si koridora bakar; y = duvar tepesinin hemen altı. Birbirinden ≥MIN_SEP uzak, en fazla MAX_LAMPS.
Kullanım: python tools/maze_lamps.py <maze_grid.json>  → Map.tscn'e yapıştırılacak [node] blokları basar
"""
import sys, json, math, random

MIN_SEP = 13.0
MAX_LAMPS = 32
MOUNT_Y = 2.75
random.seed(7)  # deterministik — yeniden üretince aynı noktalar

g = json.load(open(sys.argv[1]))
xs, zs, grid = g["xs"], g["zs"], g["grid"]
H, W = len(grid), len(grid[0])

def wall(r, c):
    return not (0 <= r < H and 0 <= c < W) or grid[r][c]

cands = []
for r in range(2, H - 2):
    for c in range(2, W - 2):
        if not grid[r][c]:
            continue
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            # önünde ≥3 hücre koridor, yan hücreler de duvar (düz yüz, köşe/uç değil)
            if any(wall(r + dr * k, c + dc * k) for k in (1, 2, 3)):
                continue
            pr, pc = dc, dr  # dik yön
            if not (wall(r + pr, c + pc) and wall(r - pr, c - pc)):
                continue
            # yüzün hemen önü (koridor tarafı yan hücreler de boş olsun — duvar dibi değil koridor ortası)
            if wall(r + dr + pr, c + dc + pc) or wall(r + dr - pr, c + dc - pc):
                continue
            face_x = xs[c] + dc * 0.5
            face_z = zs[r] + dr * 0.5
            cands.append((face_x, face_z, dc, dr))

random.shuffle(cands)
picked = []
for x, z, dx, dz in cands:
    if all(math.dist((x, z), (p[0], p[1])) >= MIN_SEP for p in picked):
        picked.append((x, z, dx, dz))
    if len(picked) >= MAX_LAMPS:
        break

print("# %d lamba" % len(picked), file=sys.stderr)
for i, (x, z, dx, dz) in enumerate(picked):
    # -Z koridora (dx, dz) baksın: x_axis = (-dz, 0, dx), z_axis = (-dx, 0, -dz)
    print('[node name="Lamp%d" type="Marker3D" parent="WallLamps"]' % i)
    print("transform = Transform3D(%g, 0, %g, 0, 1, 0, %g, 0, %g, %.2f, %.2f, %.2f)" % (-dz, dx, -dx, -dz, x, MOUNT_Y, z))
    print()
