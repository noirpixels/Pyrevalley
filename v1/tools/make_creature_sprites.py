"""Paints the prototype's creature sprites into Creatures/.

Each creature is built from simple shaded shapes at the same pixel density as
Veyl (0.0375 world units per pixel), facing right. Two files per creature:
  <id>.png       body (shaded in-game, outlined)
  <id>_glow.png  eyes / embers / cracks (unshaded in-game, so they glow at night)

Pure Python, no dependencies:  python3 tools/make_creature_sprites.py
These are placeholders: replace the PNGs with hand-made art of the same name.
"""
import math, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from png_util import write_png

OUT = os.path.join(os.path.dirname(__file__), "..", "Creatures")
LIGHT = (-0.45, -0.65, 0.62)  # from upper-left, toward viewer
OUTLINE = (11, 10, 15)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hash2(x, y, seed=0):
    n = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 32767.5 - 1.0


class Sprite:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.body = [[None] * w for _ in range(h)]      # (r,g,b) or None
        self.glow = [[(0, 0, 0, 0.0)] * w for _ in range(h)]

    # ---------- body shapes ----------
    def put(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.body[y][x] = color

    def shade(self, base, nx, ny, nz, x, y, grain):
        dot = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
        s = 0.62 + 0.55 * max(0.0, dot)
        s *= 1.0 + grain * hash2(x // 2, y // 2, 3)
        return tuple(max(0, min(255, int(c * s))) for c in base)

    def ellipse(self, cx, cy, rx, ry, color, rot=0.0, grain=0.06, rim=True):
        base = hexc(color)
        r = max(rx, ry) + 1
        cr, sr = math.cos(rot), math.sin(rot)
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                lx, ly = dx * cr + dy * sr, -dx * sr + dy * cr
                d = (lx / rx) ** 2 + (ly / ry) ** 2
                if d > 1.0:
                    continue
                nx, ny = lx / rx, ly / ry
                nz = math.sqrt(max(0.0, 1.0 - d))
                # rotate normal back to screen space
                nx, ny = nx * cr - ny * sr, nx * sr + ny * cr
                c = self.shade(base, nx, ny, nz, x, y, grain)
                if rim and d > 0.84:
                    c = tuple(int(v * 0.72) for v in c)
                self.put(x, y, c)

    def poly(self, pts, color, grain=0.06, top=None, bottom=None):
        """Filled polygon with a vertical light gradient."""
        base = hexc(color)
        ys = [p[1] for p in pts]
        y0, y1 = int(min(ys)), int(max(ys))
        for y in range(y0, y1 + 1):
            yc = y + 0.5
            xs = []
            for (ax, ay), (bx, by) in zip(pts, pts[1:] + pts[:1]):
                if (ay <= yc < by) or (by <= yc < ay):
                    xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
            xs.sort()
            t = (y - y0) / max(1, y1 - y0)
            s = (top or 1.15) * (1 - t) + (bottom or 0.7) * t
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(round(xs[i])), int(round(xs[i + 1]))):
                    c = tuple(int(v * s * (1 + grain * hash2(x // 2, y // 2, 5))) for v in base)
                    self.put(x, y, tuple(max(0, min(255, v)) for v in c))

    def stroke(self, pts, width, color, grain=0.05):
        """Thick polyline (tails, legs). width can be a (start, end) pair."""
        w0, w1 = width if isinstance(width, tuple) else (width, width)
        segs = list(zip(pts, pts[1:]))
        total = sum(math.dist(a, b) for a, b in segs) or 1
        done = 0.0
        for a, b in segs:
            n = max(1, int(math.dist(a, b)))
            for i in range(n + 1):
                t = i / n
                x = a[0] + (b[0] - a[0]) * t
                y = a[1] + (b[1] - a[1]) * t
                w = w0 + (w1 - w0) * (done + math.dist(a, b) * t) / total
                self.ellipse(x, y, w / 2, w / 2, color, grain=grain, rim=False)
            done += math.dist(a, b)

    def ring(self, cx, cy, rx, ry, thick, color, rot=0.0):
        base = hexc(color)
        r = max(rx, ry) + 1
        cr, sr = math.cos(rot), math.sin(rot)
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                lx, ly = dx * cr + dy * sr, -dx * sr + dy * cr
                d = math.sqrt((lx / rx) ** 2 + (ly / ry) ** 2)
                if 1.0 - thick / max(rx, ry) <= d <= 1.0:
                    s = 1.25 if ly < 0 else 0.75
                    self.put(x, y, tuple(min(255, int(v * s)) for v in base))

    # ---------- glow ----------
    def add_glow(self, x, y, color, a):
        if 0 <= x < self.w and 0 <= y < self.h and a > 0.01:
            old = self.glow[y][x]
            if a > old[3]:
                self.glow[y][x] = (*color, min(1.0, a))

    def glow_dot(self, cx, cy, core, halo, color, hot="#fff1c4"):
        col, hotc = hexc(color), hexc(hot)
        for y in range(int(cy - halo) - 1, int(cy + halo) + 2):
            for x in range(int(cx - halo) - 1, int(cx + halo) + 2):
                d = math.dist((x + 0.5, y + 0.5), (cx, cy))
                if d <= core:
                    k = d / max(core, 0.01)
                    c = tuple(int(hotc[i] * (1 - k) + col[i] * k) for i in range(3))
                    self.add_glow(x, y, c, 1.0)
                elif d <= halo:
                    self.add_glow(x, y, col, 0.55 * (1 - (d - core) / (halo - core)) ** 2)

    def glow_line(self, pts, core, halo, color):
        for a, b in zip(pts, pts[1:]):
            n = max(1, int(math.dist(a, b) * 2))
            for i in range(n + 1):
                t = i / n
                self.glow_dot(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, core, halo, color, hot=color)

    def glow_slit(self, cx, cy, rx, ry, color):
        self.glow_dot(cx, cy, 0, max(rx, ry) * 2.2, color)
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1:
                    self.add_glow(x, y, hexc("#fff1c4"), 1.0)

    # ---------- output ----------
    def save(self, name):
        w, h = self.w, self.h
        solid = [[self.body[y][x] is not None for x in range(w)] for y in range(h)]
        rows = []
        for y in range(h):
            row = []
            for x in range(w):
                if solid[y][x]:
                    r, g, b = self.body[y][x]
                    gr, gg, gb, ga = self.glow[y][x]
                    # bake glow cores into the body so it still reads if shaded
                    row.append((int(r + (gr - r) * ga), int(g + (gg - g) * ga), int(b + (gb - b) * ga), 255))
                elif any(solid[yy][xx] for yy in range(max(0, y - 2), min(h, y + 3))
                         for xx in range(max(0, x - 2), min(w, x + 3))
                         if abs(yy - y) + abs(xx - x) <= 3):
                    row.append((*OUTLINE, 255))
                else:
                    row.append((0, 0, 0, 0))
            rows.append(row)
        write_png(os.path.join(OUT, name + ".png"), rows)
        write_png(os.path.join(OUT, name + "_glow.png"),
                  [[(r, g, b, int(a * 255)) for (r, g, b, a) in row] for row in self.glow])
        print("wrote", name, w, "x", h)


# ============================================================
# CREATURES (all facing right; bottom row = feet)
# ============================================================

def mossling():
    s = Sprite(88, 80)
    s.ellipse(30, 72, 9, 5, "#1b261b", rim=False)
    s.ellipse(56, 72, 9, 5, "#1b261b", rim=False)
    s.ellipse(43, 50, 35, 26, "#3a5432", grain=0.12)
    for cx, cy, rx, ry in [(22, 32, 10, 7), (37, 26, 11, 8), (53, 27, 10, 7), (66, 35, 8, 6), (15, 44, 6, 6)]:
        s.ellipse(cx, cy, rx, ry, "#4f7340", grain=0.15)
    s.stroke([(44, 26), (45, 16), (47, 8)], (4, 3), "#40592f")
    s.ellipse(36, 10, 9, 4, "#6a9446", rot=-0.5)
    s.ellipse(57, 8, 10, 4, "#6a9446", rot=0.45)
    # eye sockets + pale bioluminescent eyes (3/4 view, looking right)
    s.ellipse(58, 47, 5, 6, "#0b0a0f", grain=0, rim=False)
    s.ellipse(72, 46, 4, 5.5, "#0b0a0f", grain=0, rim=False)
    s.glow_dot(58, 46, 2.5, 7, "#9dffb0", hot="#effff2")
    s.glow_dot(72, 45, 2, 6, "#9dffb0", hot="#effff2")
    # glowing moss spores
    for x, y in [(20, 52), (30, 64), (64, 62), (40, 38), (12, 46), (52, 30)]:
        s.glow_dot(x, y, 1, 4, "#7dffb4")
    s.save("mossling")


def ember_wolf():
    s = Sprite(160, 116)
    dark, fur = "#16151b", "#27252f"
    # far legs
    s.poly([(38, 64), (49, 64), (47, 110), (38, 110)], dark)
    s.poly([(106, 64), (117, 64), (115, 110), (106, 110)], dark)
    # tail
    s.stroke([(32, 58), (16, 46), (9, 28), (17, 13)], (12, 6), fur, grain=0.1)
    # body
    s.ellipse(44, 64, 21, 20, fur, grain=0.1)
    s.ellipse(75, 63, 44, 20, fur, grain=0.1)
    s.ellipse(110, 61, 21, 23, fur, grain=0.1)
    s.ellipse(121, 48, 13, 18, fur, rot=0.5, grain=0.1)
    # head + snout + ears
    s.poly([(120, 30), (124, 6), (133, 27)], dark)
    s.poly([(131, 27), (140, 9), (143, 30)], dark)
    s.ellipse(132, 39, 16, 14, fur, grain=0.08)
    s.poly([(138, 33), (156, 42), (154, 51), (135, 51)], fur, top=1.05, bottom=0.75)
    s.ellipse(155, 45, 3, 3, "#050505", grain=0, rim=False)
    s.stroke([(142, 49), (152, 49)], 1.5, "#0b0a0f")
    # near legs + paws
    s.poly([(40, 68), (55, 68), (53, 108), (43, 108)], fur)
    s.ellipse(49, 109, 8, 4, dark, rim=False)
    s.poly([(110, 68), (123, 68), (121, 108), (111, 108)], fur)
    s.ellipse(118, 109, 8, 4, dark, rim=False)
    # ember markings
    s.glow_line([(40, 47), (62, 43), (88, 43), (106, 41)], 1, 4, "#ff7a2a")
    s.glow_line([(116, 36), (122, 44), (119, 54)], 0.8, 3.5, "#ff7a2a")
    s.glow_dot(17, 14, 3, 9, "#ff8a2a")
    s.glow_dot(126, 22, 0.8, 3, "#ff6a1a")
    s.glow_dot(139, 37, 2.5, 8, "#ffb347")
    s.save("ember_wolf")


def ashcrawler():
    s = Sprite(180, 78)
    near, far, plate = "#2c2930", "#19171d", "#2f2b31"
    for x in (62, 98, 134):
        s.stroke([(x, 46), (x - 9, 38), (x - 15, 74)], (5, 3), far)
    for cx, cy, rx, ry in [(30, 48, 20, 14), (57, 44, 23, 18), (87, 41, 25, 20), (117, 43, 23, 18), (142, 47, 17, 14)]:
        s.ellipse(cx, cy, rx, ry, plate, grain=0.16)
    for x, y in [(57, 26), (87, 21), (117, 25)]:
        s.poly([(x - 5, y + 4), (x, y - 7), (x + 5, y + 4)], far)
    for x in (50, 86, 122):
        s.stroke([(x, 50), (x - 9, 42), (x - 16, 75)], (5, 3), near)
    s.ellipse(160, 51, 14, 11, "#232026", grain=0.1)
    s.poly([(166, 52), (179, 56), (168, 60)], "#3a3438")
    s.poly([(164, 59), (177, 67), (166, 64)], "#3a3438")
    # molten cracks between plates
    for x in (44, 72, 102, 130):
        s.glow_line([(x, 31), (x + 2, 42), (x - 1, 54)], 1, 4.5, "#ff5a14")
    s.glow_line([(60, 34), (66, 40)], 0.6, 3, "#ff5a14")
    s.glow_line([(90, 30), (94, 36), (92, 44)], 0.6, 3, "#ff5a14")
    s.glow_dot(162, 47, 2.5, 8, "#ff4a1a")
    s.glow_dot(169, 48, 1.5, 5, "#ff4a1a")
    s.save("ashcrawler")


def ashbound():
    s = Sprite(320, 380)
    ash, dark, metal = "#2a272c", "#1a181d", "#45424b"
    # legs
    s.poly([(108, 262), (150, 262), (156, 368), (102, 368)], dark)
    s.poly([(175, 262), (217, 262), (224, 368), (170, 368)], dark)
    s.ellipse(128, 368, 32, 9, dark, rim=False)
    s.ellipse(198, 368, 32, 9, dark, rim=False)
    # arms (behind shoulders)
    s.poly([(30, 118), (86, 128), (72, 310), (24, 310)], ash, grain=0.12)
    s.poly([(236, 128), (292, 118), (298, 310), (250, 310)], ash, grain=0.12)
    s.ellipse(48, 250, 28, 52, ash, grain=0.12)
    s.ellipse(274, 250, 28, 52, ash, grain=0.12)
    # torso
    s.ellipse(162, 255, 64, 32, dark, grain=0.1)
    s.ellipse(162, 188, 96, 92, ash, grain=0.14)
    s.ellipse(74, 128, 50, 42, ash, grain=0.14)
    s.ellipse(250, 128, 50, 42, ash, grain=0.14)
    # head + horns
    s.poly([(136, 82), (104, 40), (94, 10), (116, 44), (144, 72)], dark, top=1.3, bottom=0.8)
    s.poly([(188, 82), (220, 40), (230, 10), (208, 44), (180, 72)], dark, top=1.3, bottom=0.8)
    s.ellipse(162, 100, 36, 33, "#211f24", grain=0.1)
    # hands + claws
    for hx in (48, 274):
        s.ellipse(hx, 322, 30, 19, dark, grain=0.1)
        for cx in (hx - 20, hx - 6, hx + 8, hx + 20):
            s.poly([(cx - 4, 334), (cx + 4, 334), (cx + 1, 352)], "#0f0e12")
        # shackles + broken chains
        s.ellipse(hx, 296, 32, 9, metal, grain=0.05)
        side = -1 if hx < 160 else 1
        for i, (lx, ly) in enumerate([(hx + side * 28, 308), (hx + side * 33, 322), (hx + side * 35, 337)]):
            s.ring(lx, ly, 6, 8, 2.5, metal, rot=0.5 if i % 2 else 0.0)
    # chest core + cracks
    for pts in [
        [(162, 178), (128, 140), (104, 120)], [(162, 178), (204, 146), (236, 122)],
        [(162, 178), (130, 226), (120, 258)], [(162, 178), (198, 222), (212, 254)],
        [(162, 178), (160, 140), (163, 118)], [(48, 190), (56, 240), (44, 288)],
        [(274, 190), (266, 240), (278, 288)], [(70, 110), (84, 132)], [(252, 110), (240, 134)],
    ]:
        s.glow_line(pts, 1.4, 6, "#ff5a10")
    s.glow_dot(162, 178, 18, 46, "#ff6a14", hot="#ffe9a8")
    s.glow_slit(148, 100, 7, 2.5, "#ffb030")
    s.glow_slit(176, 100, 7, 2.5, "#ffb030")
    s.glow_line([(146, 120), (153, 124), (160, 120), (167, 124), (174, 120)], 0.8, 4, "#ff7a2a")
    for x, y in [(96, 12), (228, 12)]:
        s.glow_dot(x, y, 1.5, 6, "#ff6a1a")
    s.save("ashbound")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for make in (mossling, ember_wolf, ashcrawler, ashbound):
        make()
