#!/usr/bin/env python3
"""Entertainment Value icon, exploration G: refinement of F1 vivid-spectrum. Global change:
glyphs moved 10% closer to canvas centre (anchor -330 -> -297 pre-scale, i.e.
~264px -> ~238px effective radius). Variants isolate: the move itself (01),
brighter hues (02), a non-beige ground (03), a radial-gradient ground with a
luminous centre (04), and an explicit soft star glow behind the petals (05),
plus the winning combination (06). Radial gradients allowed this round; all
gradient IDs are namespaced per file."""
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))

# ---------- color helpers ----------
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

# ---------- petal geometry (identical to a-shades v2, pre-scale) ----------
TIP = (0.0, -94.0)
BODY = [(-144.0, -242.0), (-172.0, -428.0), (172.0, -428.0), (144.0, -242.0)]  # SL BL BR SR
TILT = 9.0    # degrees, clockwise, about the tip
STROKE_W = 44

# HIG icon-grid rescale: whole mark scaled about the canvas center so the
# perceived circular mass matches a 768px circle (flat outer edges ~720px,
# petal corners graze ~784px).
MARK_SCALE = 0.80

def _tilt(p):
    t = math.radians(TILT)
    dx, dy = p[0] - TIP[0], p[1] - TIP[1]
    return (TIP[0] + dx * math.cos(t) - dy * math.sin(t),
            TIP[1] + dx * math.sin(t) + dy * math.cos(t))

def petal_d():
    pts = [TIP] + [_tilt(p) for p in BODY]
    cmds = []
    for j, (x, y) in enumerate(pts):
        cmds.append(('M' if j == 0 else 'L') + f' {512 + x:.1f} {512 + y:.1f}')
    return ' '.join(cmds) + ' Z'

PETAL_D = petal_d()
_ga = _tilt((0.0, -297.0))   # glyphs 10% inward vs exploration E/F (-330)
GLYPH_X = 512 + _ga[0]
GLYPH_YC = 512 + _ga[1]

# ---------- glyphs (centered on 0,0; currentColor; evenodd cutouts) ----------
GLYPHS = {
    "book": '''
  <g id="g-book">
    <path fill="currentColor" fill-rule="evenodd" d="M 0 -34
      C -20 -50 -60 -55 -86 -46 L -86 38 C -60 29 -20 32 0 47
      C 20 32 60 29 86 38 L 86 -46 C 60 -55 20 -50 0 -34 Z
      M -13 -20 C -27 -31 -50 -36 -68 -33 L -68 21 C -50 18 -27 21 -13 29 Z
      M 13 -20 C 27 -31 50 -36 68 -33 L 68 21 C 50 18 27 21 13 29 Z"/>
  </g>''',
    "film": '''
  <g id="g-film">
    <path fill="currentColor" fill-rule="evenodd" d="M -54 -78
      L 54 -78 Q 66 -78 66 -66 L 66 66 Q 66 78 54 78 L -54 78 Q -66 78 -66 66 L -66 -66 Q -66 -78 -54 -78 Z
      M -28 -46 L 28 -46 Q 32 -46 32 -42 L 32 42 Q 32 46 28 46 L -28 46 Q -32 46 -32 42 L -32 -42 Q -32 -46 -28 -46 Z
      M -55 -66 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 -36 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 -6  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 24  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 54  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 -66 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 -36 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 -6  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 24  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 54  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z"/>
  </g>''',
    "tv": '''
  <g id="g-tv">
    <path fill="none" stroke="currentColor" stroke-width="13" stroke-linecap="round"
          d="M 0 -30 L -30 -64 M 0 -30 L 28 -64"/>
    <path fill="currentColor" fill-rule="evenodd" d="M -68 -28
      L 68 -28 Q 84 -28 84 -12 L 84 50 Q 84 66 68 66 L -68 66 Q -84 66 -84 50 L -84 -12 Q -84 -28 -68 -28 Z
      M -62 -12 L 34 -12 Q 40 -12 40 -6 L 40 44 Q 40 50 34 50 L -62 50 Q -68 50 -68 44 L -68 -6 Q -68 -12 -62 -12 Z
      M 62 -4 a 7 7 0 1 0 0.0001 0 Z
      M 62 16 a 7 7 0 1 0 0.0001 0 Z
      M 62 36 a 7 7 0 1 0 0.0001 0 Z"/>
  </g>''',
    "pad": '''
  <g id="g-pad">
    <path fill="currentColor" fill-rule="evenodd" d="M -44 -40
      L 44 -40 Q 84 -40 84 0 Q 84 40 44 40 L -44 40 Q -84 40 -84 0 Q -84 -40 -44 -40 Z
      M -51 -21 L -37 -21 L -37 -7 L -23 -7 L -23 7 L -37 7 L -37 21 L -51 21 L -51 7 L -65 7 L -65 -7 L -51 -7 Z
      M 44 -22 a 8 8 0 1 0 0.0001 0 Z
      M 60 -3 a 8 8 0 1 0 0.0001 0 Z
      M 28 -3 a 8 8 0 1 0 0.0001 0 Z
      M 44 16 a 8 8 0 1 0 0.0001 0 Z"/>
  </g>''',
    "mic": '''
  <g id="g-mic">
    <path fill="none" stroke="currentColor" stroke-width="13" stroke-linecap="round"
          d="M -46 -34 A 46 46 0 0 0 46 -34 M 0 11 L 0 44 M -27 50 L 27 50"/>
    <path fill="currentColor" fill-rule="evenodd" d="M -26 -50
      Q -26 -76 0 -76 Q 26 -76 26 -50 L 26 -30 Q 26 -4 0 -4 Q -26 -4 -26 -30 Z
      M -14 -56 L 14 -56 Q 18 -56 18 -52 Q 18 -48 14 -48 L -14 -48 Q -18 -48 -18 -52 Q -18 -56 -14 -56 Z
      M -14 -40 L 14 -40 Q 18 -40 18 -36 Q 18 -32 14 -32 L -14 -32 Q -18 -32 -18 -36 Q -18 -40 -14 -40 Z"/>
  </g>''',
    "app": '''
  <g id="g-app">
    <path fill="currentColor" fill-rule="evenodd" d="M -20 -64
      L 20 -64 C 52 -64 64 -52 64 -20 L 64 20 C 64 52 52 64 20 64
      L -20 64 C -52 64 -64 52 -64 20 L -64 -20 C -64 -52 -52 -64 -20 -64 Z
      M -14 -47 L 14 -47 C 38 -47 47 -38 47 -14 L 47 14 C 47 38 38 47 14 47
      L -14 47 C -38 47 -47 38 -47 14 L -47 -14 C -47 -38 -38 -47 -14 -47 Z
      M 0 -10 a 10 10 0 1 0 0.0001 0 Z"/>
  </g>''',
}

ORDER = ["app", "film", "mic", "pad", "tv", "book"]
JITTER = [-4, 5, -6, 4, -5, 6]
GLYPH_SCALE = 1.0

def build_svg(bg, ramp, etch_fill_amt, etch_hi_amt, etch_sh_amt, uid="x", glow=None):
    """bg: '#hex' for a solid ground, or a list of (offset, color) stops for a
    radial gradient centred on the canvas. glow: optional dict(color, opacity,
    radius) — a soft halo painted behind the petals so it bleeds through the
    negative-space star."""
    parts = []
    parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">')
    parts.append('  <defs>')
    if isinstance(bg, list):
        parts.append(f'    <radialGradient id="bg-{uid}" cx="0.5" cy="0.5" r="0.72">')
        for off, col in bg:
            parts.append(f'      <stop offset="{off}" stop-color="{col}"/>')
        parts.append('    </radialGradient>')
    if glow:
        parts.append(f'    <radialGradient id="glow-{uid}" cx="0.5" cy="0.5" r="0.5">')
        if "stops" in glow:
            for off, col, op in glow["stops"]:
                parts.append(f'      <stop offset="{off}" stop-color="{col}" stop-opacity="{op}"/>')
        else:
            parts.append(f'      <stop offset="0" stop-color="{glow["color"]}" stop-opacity="{glow["opacity"]}"/>')
            parts.append(f'      <stop offset="0.55" stop-color="{glow["color"]}" stop-opacity="{glow["opacity"] * 0.55:.3f}"/>')
            parts.append(f'      <stop offset="1" stop-color="{glow["color"]}" stop-opacity="0"/>')
        parts.append('    </radialGradient>')
    for name, g in GLYPHS.items():
        if name in ORDER:
            parts.append(g)
    parts.append('  </defs>')
    if isinstance(bg, list):
        parts.append(f'  <rect width="1024" height="1024" fill="url(#bg-{uid})"/>')
    else:
        parts.append(f'  <rect width="1024" height="1024" fill="{bg}"/>')
    if glow:
        r = glow["radius"]
        parts.append(f'  <circle cx="512" cy="512" r="{r}" fill="url(#glow-{uid})"/>')
    parts.append(f'  <g transform="translate(512 512) scale({MARK_SCALE}) translate(-512 -512)">')
    for i in range(6):
        c = ramp[i]
        parts.append(
            f'    <path d="{PETAL_D}" fill="{c}" stroke="{c}" stroke-width="{STROKE_W}" '
            f'stroke-linejoin="round" transform="rotate({60*i} 512 512)"/>')
    for i in range(6):
        name = ORDER[i]
        c = ramp[i]
        fill = darken(c, etch_fill_amt)
        hi = lighten(c, etch_hi_amt)
        sh = darken(c, etch_sh_amt)
        tf = (f'rotate({60*i} 512 512) translate({GLYPH_X:.1f} {GLYPH_YC:.1f}) '
              f'rotate({JITTER[i] - 60*i}) scale({GLYPH_SCALE})')
        parts.append(f'    <g transform="{tf}">')
        parts.append(f'      <use href="#g-{name}" y="3" color="{hi}"/>')
        parts.append(f'      <use href="#g-{name}" y="-3" color="{sh}"/>')
        parts.append(f'      <use href="#g-{name}" color="{fill}"/>')
        parts.append('    </g>')
    parts.append('  </g>')
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'

# petal order everywhere: top (squircle), then clockwise film, mic, pad, tv, book
# F1 hues (poster ink) and the new brighter tuning (backlit candy)
BASE_L = ["#4257C2", "#8244B5", "#C22B85", "#D8402E", "#BC4F1C", "#0E7D6C"]
BASE_D = ["#4E63D1", "#9153C4", "#D13A96", "#E44E3A", "#CC5C26", "#159180"]
BRIGHT_L = ["#4A63E4", "#9550D6", "#E0339B", "#F04A32", "#E2621F", "#12A38C"]
BRIGHT_D = ["#5A73F2", "#A560E5", "#EE45AC", "#F85B41", "#EF6E2A", "#16B69D"]

CREAM = "#F2E8D5"
WARM_DARK = "#14121A"

SCHEMES = {
    # control: F1 hues untouched, cream ground, glyphs moved inward
    "01-spectrum-base": {
        "light": dict(bg=CREAM, ramp=BASE_L),
        "dark":  dict(bg=WARM_DARK, ramp=BASE_D),
    },
    # brighter, more luminous tuning: saturation AND lightness up, never pale
    "02-spectrum-bright": {
        "light": dict(bg=CREAM, ramp=BRIGHT_L),
        "dark":  dict(bg=WARM_DARK, ramp=BRIGHT_D),
    },
    # the beige test: bright hues on porcelain / neutral near-black
    "03-bg-cool": {
        "light": dict(bg="#F1F2EF", ramp=BRIGHT_L),
        "dark":  dict(bg="#131417", ramp=BRIGHT_D),
    },
    # radial ground: luminous warm centre falling to a deeper, cooler edge,
    # so the sparkle is carved out of the brightest part of the canvas
    "04-bg-gradient": {
        "light": dict(bg=[(0, "#FFF8EC"), (0.45, "#F0E5D0"), (1, "#D6CBB8")],
                      ramp=BRIGHT_L),
        "dark":  dict(bg=[(0, "#33244D"), (0.5, "#1D1630"), (1, "#0E0C15")],
                      ramp=BRIGHT_D),
    },
    # explicit soft halo behind the petals, bleeding through the star cutout
    "05-star-glow": {
        "light": dict(bg=CREAM, ramp=BRIGHT_L,
                      glow=dict(color="#FFE9B4", opacity=1.0, radius=300)),
        "dark":  dict(bg=WARM_DARK, ramp=BRIGHT_D,
                      glow=dict(radius=230, stops=[(0, "#FFD98A", 0.9),
                                                   (0.38, "#FF9E3E", 0.32),
                                                   (1, "#FF9E3E", 0)])),
    },
    # the winner combination: bright hues on the porcelain/neutral grounds of 03
    # with a whisper of the 05 star glow warming the sparkle
    "06-spectrum-combo": {
        "light": dict(bg="#F1F2EF", ramp=BRIGHT_L,
                      glow=dict(color="#FFE9B4", opacity=0.85, radius=280)),
        "dark":  dict(bg="#131417", ramp=BRIGHT_D,
                      glow=dict(radius=220, stops=[(0, "#FFD98A", 0.8),
                                                   (0.38, "#FF9E3E", 0.26),
                                                   (1, "#FF9E3E", 0)])),
    },
}

ETCH = {
    "light": dict(etch_fill_amt=0.13, etch_hi_amt=0.22, etch_sh_amt=0.30),
    "dark":  dict(etch_fill_amt=0.16, etch_hi_amt=0.18, etch_sh_amt=0.34),
}

if __name__ == "__main__":
    for slug, modes in SCHEMES.items():
        for mode, spec in modes.items():
            etch = spec.get("etch", ETCH[mode])
            svg = build_svg(spec["bg"], spec["ramp"], uid=f"{slug}-{mode}",
                            glow=spec.get("glow"), **etch)
            path = os.path.join(OUT, f"{slug}-{mode}.svg")
            with open(path, "w") as f:
                f.write(svg)
            print(path)
