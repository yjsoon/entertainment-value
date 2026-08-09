# WhatFun icon in Icon Composer 2 (WWDC26 / iOS 27)

Icon Composer 2 shipped as a beta alongside SF Symbols 8 after WWDC26. What it
adds over the original Icon Composer, per Apple's announcements: per-layer
**refraction** (layers pick up and transmit colour and shape from what's behind
them, dialable from a subtle edge bend to lens-like distortion), stronger
**specular highlights**, **extended previews** with dynamic lighting, and
**annotations across appearance modes**. Separately, iOS 27 gives users a
system **transparency slider** for Liquid Glass (fully clear → fully tinted)
and renders glass with darkened edges and brighter speculars.

## Strategy for this bundle

`AppIcon.icon` here deliberately stays in the original (verified) icon.json
schema rather than guessing at undocumented Icon Composer 2 keys — an invalid
key risks a failed parse, while an older document opens and migrates cleanly.
Treat this bundle as the input; apply the IC2-only settings in the app:

1. Open `AppIcon.icon` in Icon Composer 2 (it will migrate the document on
   save; keep a copy of the original if you want to stay dual-version).
2. **Petals layer** (the chips) — enable refraction at low strength (start ~20–25%): the
   lapped chips are the glass slab, and a subtle edge bend where chips overlap
   sells the stacking without distorting the glyphs. Keep specular ON; with
   iOS 27's brighter speculars, if the rim reads hot, pull specular intensity
   down a notch rather than off.
3. **Glyphs layer** — refraction OFF, specular OFF (they are engravings; the
   letterpress emboss is baked into the artwork).
4. **Background** — no refraction. The dark appearance fill is already set to
   the approved night navy `#131D44`.
5. Use IC2's extended preview to sweep the new user transparency slider from
   clear to tinted and check the icon at both extremes (plus the dynamic
   lighting preview at tilt).

## Design caveats specific to this icon under iOS 27

- **Tinted/mono rendering:** the six chip hues are deliberately value-matched,
  so a luminance-mapped mono rendition flattens them toward a single grey.
  The icon still reads — the star cutout and the embossed glyphs carry the
  silhouette — but if you want chip separation in tinted mode, use IC2's
  per-appearance annotation to deepen alternate chips' values in the mono
  variant rather than changing the colour design.
- **Fully-clear extreme:** the star cutout becomes a literal window to the
  wallpaper — the design's best trick; nothing to fix, just check it.
- The star is a transparent hole in the chips layer, so refraction applies to
  its inner edges too — at high refraction strengths the star's rim will lens
  the background. Tasteful at low strength; gaudy above ~40%.

## Verification status

Confirmed via WWDC26 coverage: IC2's existence, refraction/specular/preview/
annotation features, the iOS 27 transparency slider, and unchanged
drag-into-Xcode wiring. NOT publicly documented (and therefore not attempted
here): the icon.json v2 schema additions for refraction and annotations.
Once you save from Icon Composer 2, diff the migrated icon.json against this
one and the delta is exactly Apple's v2 vocabulary — a useful reference if we
later want to generate IC2 documents directly.
