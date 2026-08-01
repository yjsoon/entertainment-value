# Icon explorations

Riffs on the current pinwheel app icon, produced July 2026. All icons are
1024×1024 vector SVGs; every variation ships in a light and a dark build. `gallery.html`
is a self-contained side-by-side viewer for all of them (open it in any browser).

The brief, from feedback on the current icon:

- Replace the mixed palette with progressive shades of a single hue.
- Keep the negative-space center sparkle; explore other shapes the center could form.
- Make the media glyphs lighter — etched out of the surface rather than dark stamps.
- Provide a dark-mode version of everything.
- Explore what the iOS 26 Icon Composer layered format could add.

## a-shades — progressive shades, etched glyphs

Four single-hue tonal ramps (ember, ocean, plum, moss). Six petals step light → deep
clockwise from the top card; glyphs are debossed tone-on-tone with a subtle
highlight/shadow fringe. `gen.py` regenerates all SVGs; ramps are one-line edits.
After review, ember advanced: `05-ember-v2` rebalances the whole ramp so the lightest
card separates from the cream background and fills the formerly blank top petal with a
generic app-squircle glyph; `06-ember-v3` is a moodier alternative with a deeper start.

## b-centers — negative-space center shapes

Same pinwheel language and ember ramp, with the petal tips re-carved so the true
negative space forms a play button, a camera aperture, a five-point rating star, or a
heart. `gen_b_centers.py` regenerates the set.

## i-final — the approved icon

The shipped design, baked from the approved configurator state: petals #DD5A46
#E27C46 #C0A02A #229682 #5769C7 #9F75C7 on a warm-white radial ground (#FFF7F0,
37% depth), no glow, mark at 84% with 4° rotation, star opened +22, corner
rounding 90, glyphs 103% at 101% radius with 225% hand-tilt and 143% emboss.
`build_final.py` regenerates both mode SVGs and the three Icon Composer layers
from that state; the dark build derives each hue +8% lighter on a warm
near-black ground. This design is the app's `AppIcon.png`, and
`AppIcon.icon/` here is the matching Composer bundle (verify in Icon Composer
on a Mac, then wire into Xcode per `c-composer/ICON-COMPOSER-NOTES.md`).

## h-winner — round 7, the winner spec

The bright spectrum finalised: rim glow geometry-locked to the star's edges (no radial
blob — visible on porcelain in light, wash-free on the new ink-navy `#0D1430` dark
ground), star interior a different colour from the ground, an optional subtle porcelain
gradient, and an alternative coral glow colourway. `geometry.json` exports the complete
icon geometry (petal/glyph/star paths, transforms, deboss recipe, palettes, glow specs)
and `gen_h.py` rebuilds every SVG from it byte-identically. `../configurator.html` is a
self-contained interactive tuner built on that JSON: rotate the petal colours, switch
appearance, adjust grounds and glow, and download the composed SVG.

## g-spectrum — round 6, vivid spectrum refined

Six variants converging on the vivid-spectrum scheme, all with glyphs moved 10%
inward: the F1 control, a brighter "backlit candy" hue tuning, the bright hues on a
porcelain (non-beige) ground, a radial gradient ground with a luminous centre, an
explicit star glow behind the petals, and a combo (bright hues + porcelain + subtle
warm star-core) — the designer's pick. A/B testing confirmed the cream ground's
yellow cast was dirtying the cool hues. `gen_g.py` regenerates the set.

## f-vivid — round 5, saturated multi-hue

The monochromatic ramps retired after review. Five multi-hue schemes on the E
construction with chroma pushed up, the value band biased deeper (no pale cards),
and yellow excluded: vivid spectrum, sunset (burnt coral→indigo, the analogous fix),
retro pop (complementary seams), jewel, and neon dusk. Greyscale-checked per scheme,
etch depth re-tuned for the saturation. `gen_f.py` regenerates the set.

## e-pinwheel — round 4, A1v2 at Apple icon-grid size

The ember-v2 pinwheel rescaled to the HIG icon-grid circle (≈762px footprint on the
1024 canvas, corner peaks kissing the 768px reference ring) in five value-disciplined
palettes: ember (control), rebalanced ocean, analogous golden→raspberry→plum, a
greyscale-matched six-hue spectrum, and twilight periwinkle→indigo on warm paper.
Each in light and dark; `gen_e.py` regenerates the set (`MARK_SCALE = 0.80`).

## d-star — round 2, the star direction

The rating-star mark developed further after review: the five cards now physically lap
each other (deepest closes the loop over the lightest, one deliberate seam), the mark is
scaled to Apple's icon-grid proportion (740px circle on the 1024 canvas), and the glyphs
carry the full a-shades letterpress emboss. Five palette schemes — ember mono, analogous
warm sweep, matched-value five-hue spectrum, coral/teal duotone, and jewel tones — each
in light and dark. `gen_d_star.py` regenerates the set.

## c-composer — iOS 26 Icon Composer rebuild

A three-layer Liquid Glass version: background gradient, petal slab (the sparkle is a
transparent hole in this layer), and glyph layer. Includes mockups of the Default,
Dark, Clear, and Tinted dynamic modes, the separated layer sources ready to drag into
Icon Composer, and `ICON-COMPOSER-NOTES.md` with per-layer settings and Xcode wiring.
Round 3 deepened the ramp start, added the squircle glyph to the top wedge, upgraded
the glass simulation, and added home-screen context mockups (`05`/`06`) plus a
best-effort `AppIcon.icon` bundle (schema cross-checked against an open-source reader
of real Icon Composer bundles, but unverified in Icon Composer itself — see the notes
file; the drag-in-layers path remains the reliable route).
