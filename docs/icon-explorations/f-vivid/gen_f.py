#!/usr/bin/env python3
"""WhatFun icon, exploration F: the E construction (icon-grid pinwheel, sparkle,
squircle sixth glyph, letterpress deboss) carried unchanged, with five NEW
saturated multi-hue schemes. Rules from the client: chroma up, band deepened
(no pale/pastel cards against cream), no yellow/pale gold, hue assignment puts
strong cream-contrast on the top squircle card and avoids near-neighbour
adjacencies where possible. Greyscale value-matching kept as a guardrail."""
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
_ga = _tilt((0.0, -330.0))
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

def build_svg(bg, ramp, etch_fill_amt, etch_hi_amt, etch_sh_amt):
    parts = []
    parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">')
    parts.append(f'  <rect width="1024" height="1024" fill="{bg}"/>')
    parts.append('  <defs>')
    for name, g in GLYPHS.items():
        if name in ORDER:
            parts.append(g)
    parts.append('  </defs>')
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
SCHEMES = {
    # E4-spectrum with chroma up and the whole band deepened; spectral hue run
    # (indigo -> violet -> magenta -> vermilion -> burnt orange -> forest teal),
    # indigo on top for maximum cream contrast. No yellow, no olive.
    "01-vivid-spectrum": {
        "light": dict(bg="#F2E8D5",
                      ramp=["#4257C2", "#8244B5", "#C22B85", "#D8402E", "#BC4F1C", "#0E7D6C"]),
        "dark":  dict(bg="#14121A",
                      ramp=["#4E63D1", "#9153C4", "#D13A96", "#E44E3A", "#CC5C26", "#159180"]),
    },
    # E3-analogous with the golden step removed: burnt coral sweeping through
    # raspberry and magenta into deep indigo; keeps the progressive value read
    "02-sunset": {
        "light": dict(bg="#F6EAD8",
                      ramp=["#D4562F", "#D8404C", "#C92F67", "#A82E82", "#7C3193", "#462D8C"]),
        "dark":  dict(bg="#1C0F16",
                      ramp=["#DD6136", "#E04B55", "#D43A72", "#B43A8E", "#8A3FA1", "#54389E"]),
    },
    # saturated 70s board-game-box palette; complementary bounces on every seam
    # (navy/burnt orange, orange/teal, teal/brick, brick/forest, forest/magenta)
    "03-retro-pop": {
        "light": dict(bg="#F0E7D2",
                      ramp=["#40578F", "#A84D1C", "#16766F", "#B33A2B", "#2E6B33", "#AF2D6E"]),
        "dark":  dict(bg="#171310",
                      ramp=["#46609F", "#C4602A", "#1C857D", "#C44730", "#377B3C", "#C23A7D"]),
    },
    # d-star jewel family on six petals: sapphire top, then ruby, emerald,
    # amber-brown, amethyst, garnet — deepest band of the five schemes
    "04-jewel": {
        "light": dict(bg="#F1E9DB",
                      ramp=["#1D4E9E", "#B01E42", "#0C7048", "#8C4E1B", "#71399C", "#8A2433"],
                      etch=dict(etch_fill_amt=0.15, etch_hi_amt=0.26, etch_sh_amt=0.32)),
        "dark":  dict(bg="#141016",
                      ramp=["#2A5FB5", "#C22A50", "#12855C", "#A05E22", "#8348B0", "#9C2E3E"],
                      etch=dict(etch_fill_amt=0.18, etch_hi_amt=0.22, etch_sh_amt=0.36)),
    },
    # designer's pick: neon-dusk — arcade-cabinet saturation (cobalt, electric
    # magenta, petrol teal, deep coral, ultraviolet, raspberry), cool/hot
    # alternation so every seam snaps
    "05-neon-dusk": {
        "light": dict(bg="#F2EADC",
                      ramp=["#2C55C0", "#D6248E", "#0A8278", "#C63F26", "#6931B8", "#B01E55"]),
        "dark":  dict(bg="#120F1A",
                      ramp=["#3D66D4", "#E93AA2", "#0E968A", "#E85A3C", "#7B42CC", "#C22C66"]),
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
            svg = build_svg(spec["bg"], spec["ramp"], **etch)
            path = os.path.join(OUT, f"{slug}-{mode}.svg")
            with open(path, "w") as f:
                f.write(svg)
            print(path)
