#!/usr/bin/env python3
"""Build the final Entertainment Value icon from geometry.json + the approved configurator state.

Reproduces the configurator's render math exactly (same gamma-encoded sRGB mixes,
same transform composition), then emits:
  final-light.svg, final-dark.svg          — the icon in both modes
  layer-1-background-{light,dark}.svg      — Icon Composer background layer
  layer-2-petals.svg, layer-3-glyphs.svg   — Icon Composer content layers (transparent)
Run: python3 build_final.py
"""
import json
import math
import pathlib

HERE = pathlib.Path(__file__).parent
GEO = json.loads((HERE.parent / "h-winner" / "geometry.json").read_text())

# ---- approved configurator state (readout, 2026-08-08) ----------------------
STATE = {
    "petals_light": ["#DD5A46", "#E27C46", "#C0A02A", "#229682", "#5769C7", "#9F75C7"],
    "bg_light": "#FFF7F0", "grad_depth": 0.37,     # radial 37%
    "glow": False,
    "scale": 0.84, "rot": 4, "spread": 25, "corner": 90,
    "gsize": 1.20, "gpos": 1.00, "tilt": 1.90, "emboss": 0.72,
    "chip_tilt": 0, "lap": "alt",
}

# Chip pentagon: mirror-symmetric base rotated about its tip by chip_tilt degrees.
# At 0 the chips are symmetric, so the null-space star is perfectly even.
CHIP_TIP = (512.0, 418.0)
CHIP_BASE = [(0.0, 0.0), (-144.0, -148.05), (-171.97, -334.0), (171.97, -334.0), (144.0, -148.05)]
GLYPH_ANCHOR_BASE = (0.0, -203.05)     # on-axis, relative to the chip tip
LAP_ORDERS = {"cw": [0, 1, 2, 3, 4, 5], "ccw": [5, 4, 3, 2, 1, 0], "alt": [0, 2, 4, 1, 3, 5]}
# Dark mode, user-approved (configurator readout, 2026-08-02): the lifted petal
# hues on a night-navy radial ground. Gradient stops use the configurator's
# dark formula: centre = lighten(base, depth*0.4), edge = darken(base, depth*0.45).
DARK_PETALS = ["#E06755", "#E48655", "#C5A83B", "#349E8C", "#6475CB", "#A780CB"]
BG_DARK_BASE, BG_DARK_DEPTH = "#131D44", 0.44

PETAL_ANGLES = [0, 60, 120, 180, 240, 300]


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def hx(c):
    return "#" + "".join(f"{round(max(0, min(255, v))):02X}" for v in c)


def mix(a, b, t):
    a, b = rgb(a), rgb(b)
    return hx([av + (bv - av) * t for av, bv in zip(a, b)])


def lighten(h, t):
    return mix(h, "#FFFFFF", min(1, t))


def darken(h, t):
    return mix(h, "#000000", min(1, t))


def petals_dark():
    return list(DARK_PETALS)


def glyph_defs(suffix):
    out = [f'<g id="g-{name}-{suffix}">' + "".join(
        (f'<path fill="currentColor" fill-rule="evenodd" d="{s["d"]}"/>'
         if s["kind"] == "fill" else
         f'<path fill="none" stroke="currentColor" stroke-width="{s["width"]}" stroke-linecap="{s.get("linecap", "round")}" d="{s["d"]}"/>')
        for s in GEO["glyphs"]["shapes"][name]) + "</g>"
        for name in GEO["glyphs"]["shapes"]]
    return "".join(out)


def mark_open():
    s, r = STATE["scale"], STATE["rot"]
    return (f'<g transform="translate(512 512) scale({s}) translate(-512 -512)'
            f'{f" rotate({r} 512 512)" if r else ""}">')


def _chip_rot(x, y):
    t = math.radians(STATE["chip_tilt"])
    return x * math.cos(t) - y * math.sin(t), x * math.sin(t) + y * math.cos(t)


def petal_path():
    pts = []
    for x, y in CHIP_BASE:
        rx, ry = _chip_rot(x, y)
        pts.append(f"{CHIP_TIP[0] + rx:.1f} {CHIP_TIP[1] + ry:.1f}")
    return "M " + " L ".join(pts) + " Z"


def petal_elems(hues):
    sp, w = STATE["spread"], STATE["corner"]
    d = petal_path()
    return "".join(
        f'<path d="{d}" fill="{hues[i]}" stroke="{hues[i]}" '
        f'stroke-width="{w}" stroke-linejoin="round" '
        f'transform="rotate({PETAL_ANGLES[i]} 512 512) translate(0 {-sp})"/>'
        for i in LAP_ORDERS[STATE["lap"]])


def glyph_elems(hues, mode, suffix):
    arx, ary = _chip_rot(*GLYPH_ANCHOR_BASE)
    ax0, ay0 = CHIP_TIP[0] + arx, CHIP_TIP[1] + ary
    k, gs, sp = STATE["gpos"], STATE["gsize"], STATE["spread"]
    ax, ay = 512 + (ax0 - 512) * k, 512 + (ay0 - 512) * k
    amt = GEO["deboss"]["amounts"][mode]
    e = STATE["emboss"]
    parts = []
    for i in range(6):
        jit = GEO["glyphs"]["jitter_deg"][i] * STATE["tilt"]
        name = GEO["glyphs"]["order"][i]
        h = hues[i]
        parts.append(
            f'<g transform="rotate({PETAL_ANGLES[i]} 512 512) translate(0 {-sp}) '
            f'translate({ax:.1f} {ay:.1f}) rotate({-PETAL_ANGLES[i] + jit:.2f}) scale({gs})">'
            f'<use href="#g-{name}-{suffix}" y="3" color="{lighten(h, amt["lighten"] * e)}"/>'
            f'<use href="#g-{name}-{suffix}" y="-3" color="{darken(h, amt["darken_sh"] * e)}"/>'
            f'<use href="#g-{name}-{suffix}" color="{darken(h, amt["darken_fill"] * e)}"/></g>')
    return "".join(parts)


def bg_gradient(mode, gid):
    if mode == "light":
        c0 = lighten(STATE["bg_light"], 0.55)
        c1 = mix(STATE["bg_light"], "#B9BCB0", STATE["grad_depth"] * 0.55)
    else:
        c0 = lighten(BG_DARK_BASE, BG_DARK_DEPTH * 0.4)
        c1 = darken(BG_DARK_BASE, BG_DARK_DEPTH * 0.45)
    r = GEO["backgrounds"]["light_gradient"]["r"]
    return (f'<radialGradient id="{gid}" cx="0.5" cy="0.5" r="{r}">'
            f'<stop offset="0" stop-color="{c0}"/><stop offset="1" stop-color="{c1}"/></radialGradient>')


def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">{f"<defs>{defs}</defs>" if defs else ""}{body}</svg>')


def build_icon(mode):
    hues = STATE["petals_light"] if mode == "light" else petals_dark()
    sfx = f"final-{mode}"
    gid = f"bg-{sfx}"
    defs = bg_gradient(mode, gid) + glyph_defs(sfx)
    body = (f'<rect width="1024" height="1024" fill="url(#{gid})"/>'
            + mark_open() + petal_elems(hues) + glyph_elems(hues, mode, sfx) + "</g>")
    return svg(body, defs)


def build_layers():
    files = {}
    for mode in ("light", "dark"):
        gid = f"bg-layer-{mode}"
        files[f"layer-1-background-{mode}.svg"] = svg(
            f'<rect width="1024" height="1024" fill="url(#{gid})"/>', bg_gradient(mode, gid))
    files["layer-2-petals.svg"] = svg(
        mark_open() + petal_elems(STATE["petals_light"]) + "</g>")
    files["layer-3-glyphs.svg"] = svg(
        mark_open() + glyph_elems(STATE["petals_light"], "light", "layer") + "</g>",
        glyph_defs("layer"))
    return files


if __name__ == "__main__":
    out = {f"final-{m}.svg": build_icon(m) for m in ("light", "dark")}
    out.update(build_layers())
    for name, content in out.items():
        (HERE / name).write_text(content)
        print("wrote", name)
    # Both AppIcon.icon bundles reference Assets/petals.svg and Assets/glyphs.svg —
    # write them here so regeneration never needs a manual copy step.
    repo_root = HERE.parent.parent.parent
    for assets in (HERE / "AppIcon.icon" / "Assets",
                   repo_root / "EntertainmentValue" / "AppIcon.icon" / "Assets"):
        if assets.parent.exists():
            assets.mkdir(exist_ok=True)
            (assets / "petals.svg").write_text(out["layer-2-petals.svg"])
            (assets / "glyphs.svg").write_text(out["layer-3-glyphs.svg"])
            print("wrote", assets / "petals.svg", "and glyphs.svg")
