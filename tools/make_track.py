#!/usr/bin/env python3
"""Builds the Bethlehem Road data file the game loads (game/data/beth.json) from the Wii U road layout.

Same curve as the Wii U game (Catmull-Rom through the control points), made bigger for the phone version,
plus the open land width on each side, the boost and bounce pads, and where each piece of scenery stands.
"""
import json, math, os
import numpy as np

SCALE = 1.9           # bigger than the Wii U road: longer races, more room
PER = 40              # road samples between two control points
SHOULDER = 4.0
FIELD_MAX = 40.0

# x, y, z, width, bank  (the Wii U Bethlehem Road)
PTS = [(0, 0, 0, 12, 0), (0, 0, 50, 12, 0), (-10, 0, 95, 13, 0), (-35, .5, 120, 16, 0), (-70, 1.5, 125, 14, 0),
       (-100, 4, 110, 13, 0), (-120, 7, 80, 12, 0), (-125, 9, 45, 12, 0), (-110, 8, 15, 12, 0), (-85, 5, 0, 11, 0),
       (-70, 3, -25, 11, .12), (-95, 2, -50, 12, 0), (-75, .5, -75, 12, 0), (-40, 0, -80, 13, 0), (-15, 0, -60, 12, 0),
       (-5, 0, -30, 12, 0)]

# Wii U scenery: kind, definition sample (20 per control point), side offset, height
SCENERY = [("house", 6, -12, 7), ("lantern", 12, 11, 4), ("house2", 18, 12, 9), ("house", 26, -12, 7), ("lantern", 32, -11, 4),
           ("house2", 38, 12, 9), ("house", 46, 12, 7), ("lantern", 52, 12, 4), ("house", 58, -12, 7),
           ("palm", 66, -14, 11), ("palm", 74, 15, 12), ("well", 80, -15, 4), ("lantern", 86, 14, 4), ("palm", 92, -15, 11), ("house2", 100, 15, 9),
           ("olive", 112, -12, 6), ("olive", 122, 12, 7), ("olive", 134, -13, 6), ("sheep", 142, 12, 2.2), ("olive", 150, 13, 7),
           ("olive", 160, -12, 6), ("lantern", 168, 11, 4),
           ("stable", 180, 13, 7), ("sheep", 186, 11, 2.2), ("palm", 192, -13, 11), ("olive", 204, 12, 6),
           ("olive", 216, -12, 6), ("lantern", 226, 10, 4), ("olive", 236, 12, 7), ("house", 248, -12, 7), ("olive", 258, 13, 6),
           ("olive", 270, -12, 7), ("lantern", 280, 11, 4), ("house2", 292, 13, 9),
           ("crystal", 230, -12, 3), ("crystal", 238, 12, 3), ("crystal", 244, -12, 2.5),
           ("inn", 296, -13, 9), ("lantern", 302, 11, 4), ("house", 308, 12, 7), ("house2", 312, -12, 9), ("lantern", 316, -11, 4), ("house", 318, 12, 7)]
# extra life out in the open land (new for this version): flocks, olive groves, villagers
EXTRA = [("sheep", 140, 26, 2.2), ("sheep", 144, 30, 2.2), ("sheep", 147, 24, 2.2), ("olive", 120, -28, 7), ("olive", 128, -34, 6),
         ("villager", 70, -10, 2.0), ("villager", 84, 11, 2.0), ("stall", 76, 12, 3.5), ("stall", 62, -12, 3.5),
         ("palm", 20, -26, 12), ("palm", 40, 28, 11), ("olive", 210, -30, 7), ("olive", 262, 30, 6), ("boulder", 200, 22, 3),
         ("boulder", 222, -24, 3.5), ("brazier", 178, -10, 2.2), ("sheep", 190, 22, 2.2), ("villager", 300, 10, 2.0)]
PADS = [(26, -2.5, 2.2, "boost"), (30, 2.5, 2.2, "boost"), (78, 0, 3.0, "bounce"), (150, -3, 2.0, "boost"), (250, 0, 2.5, "boost")]


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def build():
    P = np.array(PTS, float); P[:, [0, 2]] *= SCALE; P[:, 1] *= SCALE * 1.2; P[:, 3] *= 1.15
    n = len(P); S = []
    for i in range(n):
        p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]
        for k in range(PER):
            S.append(catmull(p0, p1, p2, p3, k / PER))
    S = np.array(S); N = len(S)
    pos = S[:, :3]
    tan = np.roll(pos, -1, 0) - np.roll(pos, 1, 0); tan[:, 1] = 0; tan /= np.linalg.norm(tan, axis=1, keepdims=True)
    right = np.stack([-tan[:, 2], np.zeros(N), tan[:, 0]], 1)
    seg = np.linalg.norm(np.roll(pos, -1, 0) - pos, axis=1); dist = np.concatenate([[0], np.cumsum(seg)[:-1]]); length = seg.sum()
    # open land: walk out from the road until another part of the course gets near
    field = np.zeros((N, 2))
    for i in range(N):
        edge = S[i, 3] / 2 + SHOULDER
        for sd, side in enumerate((-1, 1)):
            got = 0
            for L in np.arange(edge + 2, edge + FIELD_MAX + 3, 2.0):
                p = pos[i, [0, 2]] + right[i, [0, 2]] * side * L
                d = np.sum((pos[:, [0, 2]] - p) ** 2, 1) - (S[:, 3] / 2) ** 2
                j = int(np.argmin(d)); di = abs(j - i); di = min(di, N - di)
                if di > 18: break
                got = L - edge
            field[i, sd] = max(0.0, got - 4.0)
    # smooth the land edge so the wall is a nice curve
    for _ in range(6): field = (np.roll(field, 1, 0) + 2 * field + np.roll(field, -1, 0)) / 4
    k = PER / 20.0
    scen = [dict(kind=a, idx=int(round(b * k)) % N, side=c * 1.15 * (1.0 if abs(c) > 20 else 1.0), h=d) for a, b, c, d in SCENERY + EXTRA]
    pads = [dict(idx=int(round(a * k)) % N, lat=b, half=c, kind=d) for a, b, c, d in PADS]
    star = [-230 * SCALE, 150, 60 * SCALE]
    return dict(name="Bethlehem Road", laps=3, n=N, length=float(length), shoulder=SHOULDER,
                x=pos[:, 0].round(3).tolist(), y=pos[:, 1].round(3).tolist(), z=pos[:, 2].round(3).tolist(),
                width=S[:, 3].round(3).tolist(), bank=S[:, 4].round(4).tolist(), dist=dist.round(3).tolist(),
                field_l=field[:, 0].round(2).tolist(), field_r=field[:, 1].round(2).tolist(),
                scenery=scen, pads=pads, star=star, shortcut=[int(300 * k) % N, int(335 * k) % N])


if __name__ == "__main__":
    d = build()
    out = os.path.join(os.path.dirname(__file__), "..", "game", "data", "beth.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(d, open(out, "w"))
    print("samples", d["n"], "length %.0f m" % d["length"], "min/max field", min(d["field_l"] + d["field_r"]), max(d["field_l"] + d["field_r"]))
