// Grid — Flutter FragmentProgram shader
// Divides the image into a grid of rounded square cells (~60-65px each).
// Every cell acts as an independent convex glass lens: pixels inside are
// radially displaced outward from the cell centre (fish-eye per cell).
// Cell borders appear as thick glass dividers with a fresnel-like highlight.
//
// Visual character (from reference screenshot):
//   • Regular grid of ~65px rounded-square cells covers the whole image.
//   • Each cell bulges content outward from its centre (barrel distortion).
//   • Bright specular highlight lines appear at cell edges (glass divider).
//   • 4-way spiked artefact at grid intersections (corners of 4 neighbouring
//     cells all pulling in different directions simultaneously).
//   • Distortion is stronger in high-contrast areas; near-uniform regions
//     (sky) show only the faint grid outline.
//   • Cell content can invert/mirror near the edge at full intensity.
//
// Uniform layout (Flutter passes floats before samplers):
//   index 0  → uWidth     (image width  in logical pixels)
//   index 1  → uHeight    (image height in logical pixels)
//   index 2  → uIntensity (effect strength 0.0 – 1.0)
//   sampler 0 → uTexture  (source image)

#include <flutter/runtime_effect.glsl>

// ── Uniforms ──────────────────────────────────────────────────────────────────
uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform sampler2D uTexture;

// ── Output ───────────────────────────────────────────────────────────────────
out vec4 fragColor;

// ── Constants ────────────────────────────────────────────────────────────────

// Cell size in pixels — ~60-65px gives the grid density matching the reference.
const float CELL_PX          = 62.0;

// Maximum radial displacement (as a fraction of half-cell size) at full
// intensity. 1.0 = extreme outward push; 0.35 is calibrated to match the lens
// strength in the reference (content near border can just barely invert).
const float LENS_STRENGTH    = 0.35;

// Power of the radial lens profile. 1 = linear push; 2 = quadratic (stronger
// near centre, rapid fall-off toward edge). The reference looks slightly super-
// linear, so we use ~1.6.
const float LENS_POWER       = 1.6;

// Border band width as a fraction of cell size — the glass divider is roughly
// 3-4% of the cell, giving ~2px on a 62px cell.
const float BORDER_FRAC      = 0.042;

// Fresnel highlight band just inside the border — thin bright rim.
// Width as fraction of cell.
const float HIGHLIGHT_FRAC   = 0.028;

// Highlight brightness boost factor mixed into the final colour.
const float HIGHLIGHT_STRENGTH = 0.55;

// Rounded-corner softness: cells have a slight corner radius. The corner
// distance field is computed in cell-UV space. Values closer to 0.5 give
// rounder corners. 0.38 ≈ the rounded-square look in the reference.
const float CORNER_RADIUS    = 0.38;

// Minimum borderMask value to be considered "in the border region" (0→1).
const float BORDER_THRESHOLD = 0.0;

// ── Helpers ───────────────────────────────────────────────────────────────────

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec4 sampleTex(vec2 uv) {
    return texture(uTexture, uv);
}

// Signed-distance-field for a rounded square in [-0.5, 0.5]^2 UV space.
// Returns 0 at the "corner radius" boundary, negative inside, positive outside.
float roundedSquareSDF(vec2 p, float r) {
    vec2 q = abs(p) - vec2(0.5 - r);
    return length(max(q, 0.0)) - r;
}

// ── Main ──────────────────────────────────────────────────────────────────────
void main() {
    // Flutter gives us fragment coords in pixels (origin = top-left).
    vec2 fragCoord = FlutterFragCoord().xy;

    // Normalised UV in [0, 1].
    vec2 uv = fragCoord / vec2(uWidth, uHeight);

    // ── 1. Cell coordinates ───────────────────────────────────────────────────
    // cellUV: normalised position within the current cell [0, 1].
    // cellIndex: integer grid address of the cell.
    vec2 cellSizeNorm = vec2(CELL_PX) / vec2(uWidth, uHeight);
    vec2 cellIndex    = floor(uv / cellSizeNorm);
    vec2 cellFrac     = fract(uv / cellSizeNorm);           // [0,1] within cell
    vec2 cellCenter   = (cellIndex + 0.5) * cellSizeNorm;   // cell centre in UV

    // Remap cellFrac to [-0.5, 0.5] for radial calculations.
    vec2 cellP = cellFrac - 0.5;   // centred: -0.5…+0.5

    // ── 2. Rounded-square border mask ────────────────────────────────────────
    // SDF of the rounded square; positive = outside the rounded square (border
    // or corner region), negative = inside the cell body.
    float sdf = roundedSquareSDF(cellP, CORNER_RADIUS);

    // Inner and outer thresholds in SDF units (fraction of half-cell).
    // We convert from UV fraction → SDF-space by multiplying by 0.5 / 0.5 = 1
    // (the SDF is already in [-0.5, 0.5]^2 space).
    float borderOuter    = BORDER_FRAC     * 0.5;
    float highlightOuter = HIGHLIGHT_FRAC  * 0.5;

    // borderMask: 1 inside the "glass pane", 0 in the divider groove.
    // smoothstep gives a soft anti-aliased border.
    float cellBody       = 1.0 - smoothstep(-borderOuter * 0.3, borderOuter, sdf);

    // Highlight mask: 1 just inside the border edge (fresnel rim), 0 elsewhere.
    float highlightMask  = smoothstep(highlightOuter * 2.0, highlightOuter * 0.2, sdf + borderOuter)
                         * smoothstep(-highlightOuter * 2.0, 0.0, sdf);

    // ── 3. Convex lens radial displacement ───────────────────────────────────
    // Direction from cell centre to current pixel (in UV space).
    vec2  lensDir    = cellP * 2.0;           // -1…+1 in each axis
    float lensDist   = length(lensDir);        // 0 at centre, √2 at corner

    // Outward displacement magnitude: power-law profile, zero at centre,
    // maximum at cell boundary.
    // We clamp dist to avoid over-displacement in corner regions.
    float distClamped  = clamp(lensDist, 0.0, 1.0);
    float lensProfile  = pow(distClamped, LENS_POWER);  // 0→1

    // Scale by half-cell-size in UV space so the displacement is in pixel units.
    vec2 halfCell = cellSizeNorm * 0.5;

    // Displacement vector: pushes the *sample* origin inward (toward centre)
    // → content from the centre appears magnified / pushed outward visually.
    // We subtract from uv so we sample "from behind" the displaced point.
    vec2 lensOffsetUV = normalize(lensDir + 1e-6)
                       * lensProfile
                       * LENS_STRENGTH
                       * uIntensity
                       * halfCell;

    // ── 4. Edge-aware strength modulation ────────────────────────────────────
    // Sample a small neighbourhood at the cell centre to measure local contrast.
    // High-contrast cells (over mountain/sky boundary) show stronger distortion.
    float edgeDX = 3.0 / uWidth;
    float edgeDY = 3.0 / uHeight;
    float lumaC  = luma(sampleTex(cellCenter).rgb);
    float lumaL  = luma(sampleTex(cellCenter + vec2(-edgeDX, 0.0)).rgb);
    float lumaR  = luma(sampleTex(cellCenter + vec2( edgeDX, 0.0)).rgb);
    float lumaU  = luma(sampleTex(cellCenter + vec2(0.0, -edgeDY)).rgb);
    float lumaD  = luma(sampleTex(cellCenter + vec2(0.0,  edgeDY)).rgb);
    float edgeMag = sqrt(
        pow(lumaR - lumaL, 2.0) + pow(lumaD - lumaU, 2.0)
    );

    // Blend base lens with a slight edge boost (max 1.5× at sharp edges).
    float edgeMod = 1.0 + edgeMag * 1.5 * uIntensity;
    lensOffsetUV *= edgeMod;

    // ── 5. Apply displacement only inside cell body ───────────────────────────
    // Inside the border groove (cellBody ≈ 0) we sample straight through
    // to get the dark glass-divider look. Inside the body, apply full lens.
    vec2 displacedUV = uv - lensOffsetUV * cellBody;

    // ── 6. Clamp to [0, 1] ───────────────────────────────────────────────────
    vec2 finalUV = clamp(displacedUV, 0.0, 1.0);

    // ── 7. Sample displaced colour ────────────────────────────────────────────
    vec4 col = sampleTex(finalUV);

    // ── 8. Fresnel highlight rim on cell border ───────────────────────────────
    // Adds a bright specular-like rim just inside each cell edge, giving the
    // glass tile lip / embossed look visible in the reference screenshot.
    vec3 highlight = vec3(1.0) * highlightMask * HIGHLIGHT_STRENGTH * uIntensity;
    col.rgb += highlight;

    // ── 9. Darken border groove ───────────────────────────────────────────────
    // The divider line itself is slightly darkened (not black, just dimmer)
    // to mimic the shadow inside a glass tile's groove.
    float grooveDark = mix(0.55, 1.0, cellBody);
    col.rgb *= grooveDark;

    fragColor = col;
}
