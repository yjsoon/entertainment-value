#!/usr/bin/env python3
"""Entertainment Value icon, exploration H: the G2 "bright" winner productionised.

- Rim glow: light leaking around the edges of the negative-space star only.
  Implemented as (a) a flat, contained interior tint filling the star cutout
  (drawn slightly oversized behind the petals so its edge is always hidden),
  and (b) a blurred stroke traced along the exact star-cutout polygon, also
  behind the petals, so only the inner half of the blur shows as a luminous
  fringe. No wash anywhere else on the ground, in either mode.
- Navy dark ground (A/B tested), porcelain light ground, optional subtle
  radial light gradient.

geometry.json is the single source of truth: this script first assembles the
geometry/colour data as a JSON-serialisable dict, writes geometry.json, then
builds every SVG *from the parsed JSON only* (build_from_geo), so the export
provably round-trips."""
import json
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))

# ---------- colour helpers ----------
def h2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb2h(r, g, b):
    return '#%02X%02X%02X' % (round(r), round(g), round(b))

def mix(c, t, amt):
    a = h2rgb(c); b = h2rgb(t)
    return rgb2h(*[a[i] + (b[i] - a[i]) * amt for i in range(3)])

def lighten(c, amt): return mix(c, '#FFFFFF', amt)
def darken(c, amt):  return mix(c, '#000000', amt)

# ---------- petal geometry (identical to E/F/G, pre-scale) ----------
TIP = (0.0, -94.0)
BODY = [(-144.0, -242.0), (-172.0, -428.0), (172.0, -428.0), (144.0, -242.0)]
TILT = 9.0
STROKE_W = 44
MARK_SCALE = 0.80
GLYPH_ANCHOR_LOCAL = (0.0, -297.0)   # G-round "glyphs inward" anchor

def _tilt(p):
    t = math.radians(TILT)
    dx, dy = p[0] - TIP[0], p[1] - TIP[1]
    return (TIP[0] + dx * math.cos(t) - dy * math.sin(t),
            TIP[1] + dx * math.sin(t) + dy * math.cos(t))

def petal_d():
    pts = [TIP] + [_tilt(p) for p in BODY]
    return ' '.join(('M' if j == 0 else 'L') + f' {512 + x:.1f} {512 + y:.1f}'
                    for j, (x, y) in enumerate(pts)) + ' Z'

PETAL_D = petal_d()
_ga = _tilt(GLYPH_ANCHOR_LOCAL)
GLYPH_X, GLYPH_YC = 512 + _ga[0], 512 + _ga[1]

# ---------- exact star-cutout polygon ----------
# The cutout is bounded by the petals' *stroked* outlines: every point of the
# cutout is >= STROKE_W/2 away from every petal polygon (round joins make the
# stroked outline exactly the polygon dilated by 22px). Valley = innermost
# point of the tip's round-join arc. Spike = the point of maximum radius in
# the gap that keeps 22px clearance from both neighbouring petals (found
# numerically: the closure involves the shoulder join arcs, not the extended
# tip edges). Spikes are pulled 3px inward so the glow stroke always hides
# under the petals at the closure.
def _rot(p, deg):
    t = math.radians(deg)
    return (p[0] * math.cos(t) - p[1] * math.sin(t),
            p[0] * math.sin(t) + p[1] * math.cos(t))

def _pt_seg_d(p, a, b):
    ax, ay = a; bx, by = b
    vx, vy = bx - ax, by - ay
    t = ((p[0] - ax) * vx + (p[1] - ay) * vy) / (vx * vx + vy * vy)
    t = max(0.0, min(1.0, t))
    return math.hypot(p[0] - (ax + vx * t), p[1] - (ay + vy * t))

def _pt_poly_d(p, poly):
    return min(_pt_seg_d(p, poly[k], poly[(k + 1) % len(poly)])
               for k in range(len(poly)))

def _spike():
    poly0 = [TIP] + [_tilt(q) for q in BODY]
    poly1 = [_rot(q, 60) for q in poly0]
    half = STROKE_W / 2
    best = (0.0, (0.0, 0.0))
    a = 5.0
    while a < 60.0:
        t = math.radians(a)
        dx, dy = math.sin(t), -math.cos(t)   # canvas angle, cw from petal-0 axis
        # walk outward, stop at the FIRST blockage (the inner closure; the gap
        # reopens again at the outer rim notches, so no binary search)
        r = 60.0
        lo = 0.0
        while r < 420.0:
            q = (dx * r, dy * r)
            if _pt_poly_d(q, poly0) >= half and _pt_poly_d(q, poly1) >= half:
                lo = r
                r += 1.0
            else:
                break
        if 0.0 < lo < 419.0 and lo > best[0]:
            best = (lo, (dx * lo, dy * lo))
        a += 0.25
    r, (sx, sy) = best
    pull = (r - 3.0) / r
    return (sx * pull, sy * pull)

def star_points():
    """Clockwise outline: per petal, the tip round-join arc sampled from its
    left-edge tangent point through the valley to its right-edge tangent
    point, then the spike into the next gap."""
    half = STROKE_W / 2
    SL, SR = _tilt(BODY[0]), _tilt(BODY[3])
    pts5 = [TIP, SL, _tilt(BODY[1]), _tilt(BODY[2]), SR]
    cx = sum(p[0] for p in pts5) / 5
    cy = sum(p[1] for p in pts5) / 5

    def outward_normal(edge_end):
        dx, dy = edge_end[0] - TIP[0], edge_end[1] - TIP[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        mx, my = (TIP[0] + edge_end[0]) / 2, (TIP[1] + edge_end[1]) / 2
        if (cx - mx) * nx + (cy - my) * ny > 0:
            nx, ny = -nx, -ny
        return nx, ny

    nL, nR = outward_normal(SL), outward_normal(SR)
    aL = math.atan2(nL[1], nL[0])
    aR = math.atan2(nR[1], nR[0])
    # valley direction: from tip toward canvas centre
    aV = math.atan2(-TIP[1], -TIP[0])

    def near(a, ref):
        while a - ref > math.pi: a -= 2 * math.pi
        while a - ref < -math.pi: a += 2 * math.pi
        return a
    aL, aR = near(aL, aV), near(aR, aV)

    arc = []
    N = 8
    for k in range(N + 1):
        a = aL + (aR - aL) * k / N
        arc.append((TIP[0] + half * math.cos(a), TIP[1] + half * math.sin(a)))
    s0 = _spike()
    pts = []
    for i in range(6):
        pts.extend(_rot(q, 60 * i) for q in arc)
        pts.append(_rot(s0, 60 * i))
    return pts

def star_d():
    pts = star_points()
    return ' '.join(('M' if j == 0 else 'L') + f' {512 + x:.1f} {512 + y:.1f}'
                    for j, (x, y) in enumerate(pts)) + ' Z'

STAR_D = star_d()

# ---------- glyph shapes as data (fill/stroke primitives) ----------
GLYPH_SHAPES = {
    "book": [
        {"kind": "fill", "d": "M 0 -34 C -20 -50 -60 -55 -86 -46 L -86 38 C -60 29 -20 32 0 47 C 20 32 60 29 86 38 L 86 -46 C 60 -55 20 -50 0 -34 Z M -13 -20 C -27 -31 -50 -36 -68 -33 L -68 21 C -50 18 -27 21 -13 29 Z M 13 -20 C 27 -31 50 -36 68 -33 L 68 21 C 50 18 27 21 13 29 Z"},
    ],
    "film": [
        {"kind": "fill", "d": "M -54 -78 L 54 -78 Q 66 -78 66 -66 L 66 66 Q 66 78 54 78 L -54 78 Q -66 78 -66 66 L -66 -66 Q -66 -78 -54 -78 Z M -28 -46 L 28 -46 Q 32 -46 32 -42 L 32 42 Q 32 46 28 46 L -28 46 Q -32 46 -32 42 L -32 -42 Q -32 -46 -28 -46 Z M -55 -66 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M -55 -36 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M -55 -6 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M -55 24 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M -55 54 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M 43 -66 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M 43 -36 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M 43 -6 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M 43 24 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z M 43 54 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z"},
    ],
    "tv": [
        {"kind": "stroke", "d": "M 0 -30 L -30 -64 M 0 -30 L 28 -64", "width": 13, "linecap": "round"},
        {"kind": "fill", "d": "M -68 -28 L 68 -28 Q 84 -28 84 -12 L 84 50 Q 84 66 68 66 L -68 66 Q -84 66 -84 50 L -84 -12 Q -84 -28 -68 -28 Z M -62 -12 L 34 -12 Q 40 -12 40 -6 L 40 44 Q 40 50 34 50 L -62 50 Q -68 50 -68 44 L -68 -6 Q -68 -12 -62 -12 Z M 62 -4 a 7 7 0 1 0 0.0001 0 Z M 62 16 a 7 7 0 1 0 0.0001 0 Z M 62 36 a 7 7 0 1 0 0.0001 0 Z"},
    ],
    "pad": [
        {"kind": "fill", "d": "M -44 -40 L 44 -40 Q 84 -40 84 0 Q 84 40 44 40 L -44 40 Q -84 40 -84 0 Q -84 -40 -44 -40 Z M -51 -21 L -37 -21 L -37 -7 L -23 -7 L -23 7 L -37 7 L -37 21 L -51 21 L -51 7 L -65 7 L -65 -7 L -51 -7 Z M 44 -22 a 8 8 0 1 0 0.0001 0 Z M 60 -3 a 8 8 0 1 0 0.0001 0 Z M 28 -3 a 8 8 0 1 0 0.0001 0 Z M 44 16 a 8 8 0 1 0 0.0001 0 Z"},
    ],
    "mic": [
        {"kind": "stroke", "d": "M -46 -34 A 46 46 0 0 0 46 -34 M 0 11 L 0 44 M -27 50 L 27 50", "width": 13, "linecap": "round"},
        {"kind": "fill", "d": "M -26 -50 Q -26 -76 0 -76 Q 26 -76 26 -50 L 26 -30 Q 26 -4 0 -4 Q -26 -4 -26 -30 Z M -14 -56 L 14 -56 Q 18 -56 18 -52 Q 18 -48 14 -48 L -14 -48 Q -18 -48 -18 -52 Q -18 -56 -14 -56 Z M -14 -40 L 14 -40 Q 18 -40 18 -36 Q 18 -32 14 -32 L -14 -32 Q -18 -32 -18 -36 Q -18 -40 -14 -40 Z"},
    ],
    "app": [
        {"kind": "fill", "d": "M -20 -64 L 20 -64 C 52 -64 64 -52 64 -20 L 64 20 C 64 52 52 64 20 64 L -20 64 C -52 64 -64 52 -64 20 L -64 -20 C -64 -52 -52 -64 -20 -64 Z M -14 -47 L 14 -47 C 38 -47 47 -38 47 -14 L 47 14 C 47 38 38 47 14 47 L -14 47 C -38 47 -47 38 -47 14 L -47 -14 C -47 -38 -38 -47 -14 -47 Z M 0 -10 a 10 10 0 1 0 0.0001 0 Z"},
    ],
}

ORDER = ["app", "film", "mic", "pad", "tv", "book"]
JITTER = [-4, 5, -6, 4, -5, 6]

# ---------- G2 bright hues ----------
BRIGHT_L = ["#4A63E4", "#9550D6", "#E0339B", "#F04A32", "#E2621F", "#12A38C"]
BRIGHT_D = ["#5A73F2", "#A560E5", "#EE45AC", "#F85B41", "#EF6E2A", "#16B69D"]

PORCELAIN = "#F1F2EF"
NAVY_INK = "#0D1430"       # candidate A
NAVY_BLUE = "#122048"      # candidate B
NAVY = NAVY_INK            # chosen after A/B render (see report)

# ---------- assemble geometry.json ----------
GEO = {
    "canvas": {"width": 1024, "height": 1024, "viewBox": "0 0 1024 1024"},
    "mark": {
        "scale": MARK_SCALE,
        "transform": f"translate(512 512) scale({MARK_SCALE}) translate(-512 -512)",
        "note": "everything except the background rect lives inside this group",
    },
    "petal": {
        "d": PETAL_D,
        "fill_and_stroke": "petal colour on both",
        "stroke_width": STROKE_W,
        "stroke_linejoin": "round",
        "transforms": [f"rotate({60*i} 512 512)" for i in range(6)],
    },
    "star": {
        "d": STAR_D,
        "points": [[round(512 + x, 1), round(512 + y, 1)] for x, y in star_points()],
        "note": "exact negative-space cutout: petal tip edges offset by stroke/2, "
                "valleys at the round-join tip arcs, spikes at adjacent-edge intersections. "
                "Pre-mark-scale coords; render inside mark.transform.",
    },
    "glyphs": {
        "shapes": GLYPH_SHAPES,
        "order": ORDER,
        "jitter_deg": JITTER,
        "anchor": [round(GLYPH_X, 1), round(GLYPH_YC, 1)],
        "transforms": [
            f"rotate({60*i} 512 512) translate({GLYPH_X:.1f} {GLYPH_YC:.1f}) rotate({JITTER[i] - 60*i})"
            for i in range(6)
        ],
        "note": "colour via currentColor on each primitive; transforms are pre-mark-scale",
    },
    "deboss": {
        "layers": [
            {"role": "highlight", "offset": [0, 3], "tint": "lighten"},
            {"role": "shadow", "offset": [0, -3], "tint": "darken_sh"},
            {"role": "main", "offset": [0, 0], "tint": "darken_fill"},
        ],
        "amounts": {
            "light": {"darken_fill": 0.13, "lighten": 0.22, "darken_sh": 0.30},
            "dark":  {"darken_fill": 0.16, "lighten": 0.18, "darken_sh": 0.34},
        },
        "mixing": "per-channel mix of gamma-encoded sRGB toward #FFFFFF (lighten) / #000000 (darken)",
    },
    "hues": {
        "order_note": "petal 0 = top squircle, then clockwise: film, mic, pad, tv, book",
        "light": BRIGHT_L,
        "dark": BRIGHT_D,
    },
    "backgrounds": {
        "light_porcelain": PORCELAIN,
        "light_gradient": {"type": "radial", "cx": 0.5, "cy": 0.5, "r": 0.72,
                           "stops": [[0, "#F8F8F4"], [1, "#E9EAE5"]]},
        "dark_navy": NAVY,
        "dark_navy_rejected": NAVY_BLUE,
    },
    "rim_glow": {
        "geometry": "star.d stroked, fill none, blurred; drawn behind the petals inside "
                    "mark.transform so only the inner half of the blur shows in the cutout. "
                    "Interior: star.d filled, scaled about (512,512) by interior_scale so its "
                    "edge hides under the petals.",
        "interior_scale": 1.05,
        "light": {"interior_fill": "#FAEDD3", "stroke": "#F0A93C", "stroke_width": 24,
                  "blur_std": 8, "opacity": 0.95},
        "dark": {"interior_fill": "#1B2138", "stroke": "#FFB347", "stroke_width": 22,
                 "blur_std": 8, "opacity": 0.9},
        "alt": {
            "light": {"interior_fill": "#FBE9E2", "stroke": "#FF5A3C", "stroke_width": 24,
                      "blur_std": 8, "opacity": 0.9},
            "dark": {"interior_fill": "#241B33", "stroke": "#FF6B8A", "stroke_width": 22,
                     "blur_std": 8, "opacity": 0.85},
        },
    },
    "schemes": {
        "01-rim-glow": {
            "light": {"bg": "porcelain", "glow": "main"},
            "dark": {"bg": "navy", "glow": "main"},
        },
        "02-gradient": {
            "light": {"bg": "gradient", "glow": "main"},
        },
        "03-alt-glow": {
            "light": {"bg": "porcelain", "glow": "alt"},
            "dark": {"bg": "navy", "glow": "alt"},
        },
    },
}

# ---------- build SVGs strictly from parsed JSON ----------
def build_from_geo(geo, scheme, mode, uid):
    spec = geo["schemes"][scheme][mode]
    ramp = geo["hues"][mode]
    am = geo["deboss"]["amounts"][mode]
    glow = geo["rim_glow"][mode] if spec["glow"] == "main" else geo["rim_glow"]["alt"][mode]
    p = []
    c = geo["canvas"]
    p.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{c["width"]}" '
             f'height="{c["height"]}" viewBox="{c["viewBox"]}">')
    p.append('  <defs>')
    if spec["bg"] == "gradient":
        g = geo["backgrounds"]["light_gradient"]
        p.append(f'    <radialGradient id="bg-{uid}" cx="{g["cx"]}" cy="{g["cy"]}" r="{g["r"]}">')
        for off, col in g["stops"]:
            p.append(f'      <stop offset="{off}" stop-color="{col}"/>')
        p.append('    </radialGradient>')
    p.append(f'    <filter id="blur-{uid}" x="-30%" y="-30%" width="160%" height="160%">')
    p.append(f'      <feGaussianBlur stdDeviation="{glow["blur_std"]}"/>')
    p.append('    </filter>')
    for name in geo["glyphs"]["shapes"]:
        p.append(f'    <g id="g-{name}-{uid}">')
        for prim in geo["glyphs"]["shapes"][name]:
            if prim["kind"] == "fill":
                p.append(f'      <path fill="currentColor" fill-rule="evenodd" d="{prim["d"]}"/>')
            else:
                p.append(f'      <path fill="none" stroke="currentColor" '
                         f'stroke-width="{prim["width"]}" stroke-linecap="{prim["linecap"]}" '
                         f'd="{prim["d"]}"/>')
        p.append('    </g>')
    p.append('  </defs>')
    if spec["bg"] == "gradient":
        p.append(f'  <rect width="{c["width"]}" height="{c["height"]}" fill="url(#bg-{uid})"/>')
    elif spec["bg"] == "porcelain":
        p.append(f'  <rect width="{c["width"]}" height="{c["height"]}" '
                 f'fill="{geo["backgrounds"]["light_porcelain"]}"/>')
    else:
        p.append(f'  <rect width="{c["width"]}" height="{c["height"]}" '
                 f'fill="{geo["backgrounds"]["dark_navy"]}"/>')
    p.append(f'  <g transform="{geo["mark"]["transform"]}">')
    # star interior tint (oversized, hidden edge) + rim glow stroke, behind petals
    isc = geo["rim_glow"]["interior_scale"]
    p.append(f'    <path d="{geo["star"]["d"]}" fill="{glow["interior_fill"]}" '
             f'transform="translate(512 512) scale({isc}) translate(-512 -512)"/>')
    p.append(f'    <path d="{geo["star"]["d"]}" fill="none" stroke="{glow["stroke"]}" '
             f'stroke-width="{glow["stroke_width"]}" stroke-linejoin="round" '
             f'opacity="{glow["opacity"]}" filter="url(#blur-{uid})"/>')
    for i in range(6):
        col = ramp[i]
        pet = geo["petal"]
        p.append(f'    <path d="{pet["d"]}" fill="{col}" stroke="{col}" '
                 f'stroke-width="{pet["stroke_width"]}" stroke-linejoin="round" '
                 f'transform="{pet["transforms"][i]}"/>')
    for i in range(6):
        name = geo["glyphs"]["order"][i]
        col = ramp[i]
        fill = darken(col, am["darken_fill"])
        hi = lighten(col, am["lighten"])
        sh = darken(col, am["darken_sh"])
        p.append(f'    <g transform="{geo["glyphs"]["transforms"][i]}">')
        for layer, tint in [(geo["deboss"]["layers"][0], hi),
                            (geo["deboss"]["layers"][1], sh),
                            (geo["deboss"]["layers"][2], fill)]:
            ox, oy = layer["offset"]
            xy = (f' x="{ox}"' if ox else '') + (f' y="{oy}"' if oy else '')
            p.append(f'      <use href="#g-{name}-{uid}"{xy} color="{tint}"/>')
        p.append('    </g>')
    p.append('  </g>')
    p.append('</svg>')
    return '\n'.join(p) + '\n'

if __name__ == "__main__":
    with open(os.path.join(OUT, "geometry.json"), "w") as f:
        json.dump(GEO, f, indent=2)
    print("geometry.json")
    geo = json.loads(json.dumps(GEO))   # build strictly from JSON-serialised data
    for scheme, modes in GEO["schemes"].items():
        for mode in modes:
            uid = f"{scheme}-{mode}"
            svg = build_from_geo(geo, scheme, mode, uid)
            path = os.path.join(OUT, f"{scheme}-{mode}.svg")
            with open(path, "w") as f:
                f.write(svg)
            print(path)
