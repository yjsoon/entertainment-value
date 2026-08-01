#!/usr/bin/env python3
"""Build the final WhatFun icon from geometry.json + the approved configurator state.

Reproduces the configurator's render math exactly (same linear sRGB mixes,
same transform composition), then emits:
  final-light.svg, final-dark.svg          — the icon in both modes
  layer-1-background-{light,dark}.svg      — Icon Composer background layer
  layer-2-petals.svg, layer-3-glyphs.svg   — Icon Composer content layers (transparent)
Run: python3 build_final.py
"""
import json
import pathlib

HERE = pathlib.Path(__file__).parent
GEO = json.loads((HERE.parent / "h-winner" / "geometry.json").read_text())

# ---- approved configurator state (light readout, 2026-08-01) ----------------
STATE = {
    "petals_light": ["#DD5A46", "#E27C46", "#C0A02A", "#229682", "#5769C7", "#9F75C7"],
    "bg_light": "#FFF7F0", "grad_depth": 0.37,     # radial 37%
    "glow": False,
    "scale": 0.84, "rot": 4, "spread": 22, "corner": 90,
    "gsize": 1.03, "gpos": 1.01, "tilt": 2.25, "emboss": 1.43,
}
# Dark mode is a derivation (not user-tuned): each hue lifted ~8% toward white
# for legibility on the warm near-black ground, matching how earlier rounds
# built their dark twins.
DARK_LIFT = 0.08
BG_DARK_CENTER, BG_DARK_EDGE = "#221A16", "#120D0B"

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
    return [lighten(h, DARK_LIFT) for h in STATE["petals_light"]]


def glyph_defs(suffix):
    out = [f'<g id="g-{name}-{suffix}">' + "".join(
        (f'<path fill="currentColor" fill-rule="evenodd" d="{s["d"]}"/>'
         if s["kind"] == "fill" else
         f'<path fill="none" stroke="currentColor" stroke-width="{s.get("stroke_width", 13)}" stroke-linecap="round" d="{s["d"]}"/>')
        for s in GEO["glyphs"]["shapes"][name]) + "</g>"
        for name in GEO["glyphs"]["shapes"]]
    return "".join(out)


def mark_open():
    s, r = STATE["scale"], STATE["rot"]
    return (f'<g transform="translate(512 512) scale({s}) translate(-512 -512)'
            f'{f" rotate({r} 512 512)" if r else ""}">')


def petal_elems(hues):
    sp, w = STATE["spread"], STATE["corner"]
    return "".join(
        f'<path d="{GEO["petal"]["d"]}" fill="{hues[i]}" stroke="{hues[i]}" '
        f'stroke-width="{w}" stroke-linejoin="round" '
        f'transform="rotate({PETAL_ANGLES[i]} 512 512) translate(0 {-sp})"/>'
        for i in range(6))


def glyph_elems(hues, mode, suffix):
    ax0, ay0 = GEO["glyphs"]["anchor"]
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
        c0, c1 = BG_DARK_CENTER, BG_DARK_EDGE
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
