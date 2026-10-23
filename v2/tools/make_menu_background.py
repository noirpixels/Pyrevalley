"""Paints the main menu's Emberwood-at-dusk backdrop into Menu/.

Four layers, back to front, so the menu can parallax them:
  sky.png   opaque gradient, stars, cloud bands, the low ember sun
  far.png   hazy distant ridge of pines
  mid.png   darker pine line, rim-lit by the sun
  near.png  near-black framing pines and the forest floor

Pure Python, no dependencies:  python3 tools/make_menu_background.py
"""
import math, os, random, sys

sys.path.insert(0, os.path.dirname(__file__))
from png_util import write_png

OUT = os.path.join(os.path.dirname(__file__), "..", "Menu")
W, H = 1920, 1080
SUN = (W * 0.5, H * 0.6)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def hash1(n, seed=0):
    n = (n * 374761393 + seed * 668265263) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def hash2(x, y, seed=0):
    return hash1(x * 73856093 ^ y * 19349663, seed)


def noise1(x, seed=0):
    i = math.floor(x)
    f = x - i
    f = f * f * (3 - 2 * f)
    return hash1(i, seed) * (1 - f) + hash1(i + 1, seed) * f


def noise2(x, y, seed=0):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash2(ix, iy, seed), hash2(ix + 1, iy, seed)
    c, d = hash2(ix, iy + 1, seed), hash2(ix + 1, iy + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm1(x, seed=0, octaves=4):
    v, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        v += noise1(x, seed + o) * amp
        tot += amp
        x *= 2.03
        amp *= 0.5
    return v / tot


def fbm2(x, y, seed=0, octaves=4):
    v, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        v += noise2(x, y, seed + o) * amp
        tot += amp
        x, y = x * 2.03, y * 2.03
        amp *= 0.5
    return v / tot


# ---------------------------------------------------------------- sky

def paint_sky():
    # Painted at half size; the menu draws it with linear filtering.
    w, h = W // 2, H // 2
    sx, sy = SUN[0] / 2, SUN[1] / 2
    top, upper, lower, horizon = hexc("0b0a1c"), hexc("2a1838"), hexc("7a2e3a"), hexc("f08a3a")
    rows = []
    for y in range(h):
        v = y / h
        if v < 0.35:
            base = mix(top, upper, v / 0.35)
        elif v < 0.52:
            base = mix(upper, lower, (v - 0.35) / 0.17)
        else:
            base = mix(lower, horizon, (v - 0.52) / 0.12)
        row = []
        for x in range(w):
            c = base
            # Cloud bands: stretched fbm, lit warm from below near the sun.
            n = fbm2(x / 160.0, y / 38.0, 11)
            band = smooth(0.52, 0.72, n) * smooth(0.05, 0.25, v) * (1 - smooth(0.5, 0.62, v))
            d = math.hypot(x - sx, (y - sy) * 1.6)
            lit = math.exp(-d / 260.0)
            cloud = mix(hexc("1a1028"), hexc("e06a3a"), lit * 1.3 + v * 0.6)
            c = mix(c, cloud, band * 0.75)
            # Sun: a hot core inside a wide bloom.
            dd = math.hypot(x - sx, y - sy)
            c = mix(c, hexc("ffb060"), math.exp(-dd / 70.0) * 0.8)
            c = mix(c, hexc("fff0c8"), smooth(26, 20, dd))
            # Stars, fading out toward the glow.
            if v < 0.4 and hash2(x, y, 3) > 0.9965:
                tw = hash2(x, y, 4)
                c = mix(c, (255, 240, 220), (0.4 + 0.6 * tw) * (1 - v / 0.4))
            row.append((int(c[0]), int(c[1]), int(c[2]), 255))
        rows.append(row)
    return rows


# ---------------------------------------------------------------- forest layers

def new_mask():
    return [[0.0] * W for _ in range(H)]


def fill_span(mask, y, x0, x1):
    """Cover [x0, x1) on row y, with fractional coverage at both ends."""
    if y < 0 or y >= H or x1 <= x0:
        return
    row = mask[y]
    for px in range(max(0, int(math.floor(x0))), min(W, int(math.ceil(x1)))):
        cov = min(px + 1, x1) - max(px, x0)
        if cov > row[px]:
            row[px] = cov


def fill_ground(mask, line):
    for x in range(W):
        top = line[x]
        y0 = max(0, int(math.floor(top)))
        for y in range(y0, H):
            mask[y][x] = max(mask[y][x], min(1.0, y + 1 - top))


def ground_line(base, amp, freq, seed):
    return [base - (fbm1(x * freq, seed) - 0.5) * amp for x in range(W)]


def pine(mask, rng, cx, base, th, half):
    """Stacked drooping branch tiers over a thin trunk, widening toward the base."""
    seed = rng.randint(0, 9999)
    tip = base - th
    n = 5 + int(th / 55)
    tuck = 0.6 if th > 400 else 0.15  # small, distant pines read better solid
    trunk = max(1.0, half * 0.05)
    for y in range(int(tip + th * 0.3), int(base) + 1):
        fill_span(mask, y, cx - trunk, cx + trunk)
    for i in range(n):
        top = tip + th * 0.9 * i / n
        w = half * (0.12 + 0.88 * (i + 1) / n) * rng.uniform(0.85, 1.12)
        drop = max(w * rng.uniform(0.45, 0.65), th * 1.3 / n)  # overlap the next tier
        under = drop * 0.5
        lean = rng.uniform(-0.12, 0.12)
        for y in range(int(top), int(top + drop + under) + 1):
            d = y + 0.5 - top
            if d < 0:
                continue
            if d < drop:
                f = (d / drop) ** 0.85
                if i:  # lower tiers start out from the tier above, not from a point
                    f = 0.4 + 0.6 * f
            else:  # underside tucks back toward the trunk
                f = 1 - tuck * ((d - drop) / under) ** 0.7
            jl = (noise1(y * 0.4, seed + i) - 0.5) * w * 0.14
            jr = (noise1(y * 0.4, seed + i + 50) - 0.5) * w * 0.14
            fill_span(mask, y, cx - w * f * (1 - lean) + jl, cx + w * f * (1 + lean) + jr)


def pines(mask, rng, count, x0, x1, base, hmin, hmax, wscale):
    for _ in range(count):
        th = rng.uniform(hmin, hmax)
        pine(mask, rng, rng.uniform(x0, x1), base + rng.uniform(-0.03, 0.03) * th,
             th, th * wscale * rng.uniform(0.85, 1.15))


def paint_layer(mask, color, rim, rim_width, haze=None):
    """Colour a coverage mask; rim-light edges facing the sun, brighter near it."""
    rows = [[(0, 0, 0, 0)] * W for _ in range(H)]
    depth = [0.0] * W  # covered pixels directly above, per column
    for y in range(H):
        m = mask[y]
        # Distance from the nearest uncovered pixel on the sun's side of each pixel.
        side = [99.0] * W
        run = 99.0
        for x in range(int(SUN[0]), W):
            run = run + 1 if m[x] > 0.5 else 0.0
            side[x] = run
        run = 99.0
        for x in range(int(SUN[0]), -1, -1):
            run = run + 1 if m[x] > 0.5 else 0.0
            side[x] = run
        hz = smooth(H * 0.62, H, y) * 0.45 if haze else 0.0
        for x in range(W):
            a = m[x]
            depth[x] = depth[x] + 1 if a > 0.5 else 0.0
            if a <= 0:
                continue
            sun = math.exp(-math.hypot(x - SUN[0], y - SUN[1]) / 600.0)
            edge = max(1 - depth[x] / rim_width, (1 - side[x] / rim_width) * 0.8)
            c = color
            if edge > 0:
                c = mix(c, rim, edge * (0.25 + 0.75 * sun))
            if hz:
                c = mix(c, haze, hz)
            rows[y][x] = (int(c[0]), int(c[1]), int(c[2]), int(min(1.0, a) * 255))
    return rows


def paint_far(rng):
    mask = new_mask()
    fill_ground(mask, ground_line(H * 0.66, 70, 0.004, 21))
    pines(mask, rng, 260, -40, W + 40, H * 0.68, 40, 95, 0.3)
    return paint_layer(mask, hexc("8a3f4a"), hexc("ffb070"), 3, hexc("c06048"))


def paint_mid(rng):
    mask = new_mask()
    fill_ground(mask, ground_line(H * 0.76, 50, 0.006, 33))
    pines(mask, rng, 110, -60, W + 60, H * 0.78, 120, 260, 0.26)
    return paint_layer(mask, hexc("3a1a26"), hexc("ff8a40"), 4, hexc("6a2a30"))


def paint_near(rng):
    mask = new_mask()
    fill_ground(mask, ground_line(H * 0.9, 40, 0.005, 47))
    # A gap in the middle keeps the sun and the path toward it visible.
    pines(mask, rng, 5, -200, W * 0.2, H * 1.02, 700, 1250, 0.24)
    pines(mask, rng, 5, W * 0.8, W + 200, H * 1.02, 700, 1250, 0.24)
    rows = paint_layer(mask, hexc("120a10"), hexc("c0502a"), 3)
    # A worn path running toward the light.
    for y in range(int(H * 0.86), H):
        t = (y - H * 0.86) / (H * 0.14)
        half = 30 + t * 260
        cx = W * 0.5 + math.sin(t * 2.2) * 40
        for x in range(int(cx - half), int(cx + half)):
            if 0 <= x < W and rows[y][x][3] > 0:
                edge = 1 - abs(x - cx) / half
                k = smooth(0.0, 0.35, edge) * (0.55 - t * 0.35)
                c = mix(rows[y][x][:3], hexc("5a2a22"), k)
                rows[y][x] = (int(c[0]), int(c[1]), int(c[2]), rows[y][x][3])
    return rows


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(7)
    for name, paint in (("sky", paint_sky), ("far", lambda: paint_far(rng)),
                        ("mid", lambda: paint_mid(rng)), ("near", lambda: paint_near(rng))):
        write_png(os.path.join(OUT, name + ".png"), paint())
        print("wrote", name)


if __name__ == "__main__":
    main()
