# Recreating Menu Bar Icons

## Step 1: Generate Icons with Gemini

Use this prompt with Gemini (or similar AI image generator):

```
Design a set of 5 simple human figure icons for a macOS menu bar app that monitors posture while sitting.

Style requirements:
- Minimal black silhouette on white background
- Single continuous shape, no internal details
- Must be recognizable at 16x16 pixels
- Side profile view of seated human figure showing spine curvature
- No face details, no fingers, no clothing details

The 5 states:
1. Good posture - seated upright with straight spine, L-shaped chair outline
2. Bad posture - hunched seated figure with curved spine
3. Away - figure walking (user left their seat)
4. Paused - seated figure with pause symbol (two vertical bars) nearby
5. Calibrating - seated figure with alignment/crosshair lines

Show all 5 as a cohesive icon set in a single row.
```

## Step 2: Convert to SVG

Use an online vectorizer tool:
- **[SVGcode](https://svgco.de)** (recommended - free, runs in browser)
- [Vectorizer.ai](https://vectorizer.ai) (AI-powered, excellent quality)
- [Vector Magic](https://vectormagic.com) (paid, best quality)

Upload the generated image and download as SVG.

## Step 3: Crop into Individual Icons

Give Claude the SVG text with this prompt:

```
I've copied an SVG of all the icons. Crop each icon into separate SVG files with tight, square bounding boxes. The icons should be cropped as close to the edges as possible so they render at a good size in the menu bar.

Create these files in Sources/Icons/:
- posture-good.svg / .pdf
- posture-bad.svg / .pdf
- posture-away.svg / .pdf
- posture-paused.svg / .pdf
- posture-calibrating.svg / .pdf

Note: The "disabled" state reuses the paused icon, so no separate file needed.

[paste SVG here]
```

Claude will:
1. Analyze the SVG paths to find each icon's bounding box
2. Create separate SVGs with tight square viewBox crops
3. Convert to PDF using `rsvg-convert`

## Step 4: Build and Test

```bash
./build.sh && rm -rf /Applications/Posturr.app && cp -r build/Posturr.app /Applications/ && open /Applications/Posturr.app
```

## Technical Notes

- Menu bar icons should be ~18x18 points (36x36 @2x Retina)
- PDFs are vector, so source size doesn't matter - macOS scales them
- Icons must be set as template images (`isTemplate = true`) for light/dark mode
- The `MenuBarIcon` enum in `Models.swift` handles loading and resizing
