"""Labirent ızgarasından köşe/çıkmaz noktaları seçer (güç spawn noktaları için).
Köşe = duvardan ≥1 hücre uzak boş hücre; iki dik yönde (K/G + D/B) 2-3 m içinde duvar var.
Doğma noktalarına ve merkeze (kart) yakın olanlar elenir, birbirinden en az MIN_SEP uzak noktalar seçilir.
Kullanım: python tools/maze_corners.py <maze_grid.json>   (maze_convert.py çıktısı)
"""
import sys, json, math

MIN_SEP = 13.0
SPAWNS = [(-57, -39), (56, -39), (-57, 40), (56, 40)]
AVOID_SPAWN = 12.0
AVOID_CENTER = 8.0

g = json.load(open(sys.argv[1]))
xs, zs, grid = g["xs"], g["zs"], g["grid"]
H, W = len(grid), len(grid[0])

def wall(r, c):
    return not (0 <= r < H and 0 <= c < W) or grid[r][c]

def clear(r, c):
    return 1 < r < H - 2 and 1 < c < W - 2 and all(not wall(r + dr, c + dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1))

def wall_within(r, c, dr, dc, lo=2, hi=3):
    return any(wall(r + dr * k, c + dc * k) for k in range(lo, hi + 1))

cands = []
for r in range(H):
    for c in range(W):
        if not clear(r, c):
            continue
        n, s = wall_within(r, c, -1, 0), wall_within(r, c, 1, 0)
        e, w = wall_within(r, c, 0, 1), wall_within(r, c, 0, -1)
        if (n or s) and (e or w):
            p = (xs[c], zs[r])
            score = n + s + e + w  # 3 = çıkmaz sokak (tercih)
            if min(math.dist(p, q) for q in SPAWNS) < AVOID_SPAWN or math.dist(p, (0, 0)) < AVOID_CENTER:
                continue
            cands.append((score, p))

cands.sort(key=lambda t: -t[0])
picked = []
for score, p in cands:
    if all(math.dist(p, q) >= MIN_SEP for q in picked):
        picked.append(p)
print(len(picked))
for p in picked:
    print("%.1f %.1f" % p)
