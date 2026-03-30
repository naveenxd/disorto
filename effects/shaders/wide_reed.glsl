// Wide Reed — Flutter FragmentProgram shader
// Same glass-strip concept as Narrow Reed, but strips are wider (~60-80px),
// giving a thick glass-pane / architectural-column feel.
//
// Differences vs narrow_reed.glsl:
//   • STRIP_WIDTH_PX  = 70     (vs 24) — fewer, wider panes
//   • LENS_STRENGTH   = 0.55   (vs 0.38) — stronger horizontal compression
//   • EDGE_SPIKE_MUL  = 3.2    (vs 4.5) — spikes broader, less jagged
//   • BRIGHT_SPIKE_MUL= 2.4    (vs 1.8) — stronger brightness-lift per pane
//   • MAX_V_SHIFT     = 0.22   (vs 0.18) — taller columns at full intensity
//   • SINE_FREQ       = 0.72   (vs 1.1)  — slower phase change between strips
//     → adjacent wide strips shear more gently than narrow ones
//   • HORIZ_COMPRESS  = 0.14  — per-strip horizontal scale (squeezes content
//     toward strip centre), unique to wide reed per spec
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
// Strip width in pixels — wide panes give the thick glass-column look.
const float STRIP_WIDTH_PX   = 70.0;

// Pixels sampled either side when computing edge contrast.
const float EDGE_SAMPLE_OFFSET = 3.0;

// Maximum vertical shift (fraction of image height) at uIntensity = 1.
const float MAX_V_SHIFT      = 0.22;

// Phase change per strip index — lower value = slower sine transitions
// between strips → broader, smoother column separation.
const float SINE_FREQ        = 0.72;

// Horizontal lens strength: each pane acts as a thick convex glass cylinder.
// Higher than narrow because the panes are physically wider, so the compression
// must span more pixels to be visually perceptible.
const float LENS_STRENGTH    = 0.55;

// Horizontal compression: squeezes the sampled x-coordinate toward the strip
// centre, making content inside each pane look slightly narrower (tall & thin).
// This is the spec-mandated "slight horizontal compression per strip".
const float HORIZ_COMPRESS   = 0.14;

// Edge-spike multiplier — slightly lower than narrow because wide strips
// produce broader spikes, which look naturally taller without extra boost.
const float EDGE_SPIKE_MUL   = 3.2;

// Brightness lift — wide panes extrude bright areas more smoothly upward.
const float BRIGHT_SPIKE_MUL = 2.4;

// ── Helpers ───────────────────────────────────────────────────────────────────

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec4 sampleTex(vec2 uv) {
    return texture(uTexture, uv);
}

// ── Main ──────────────────────────────────────────────────────────────────────
void main() {
    // Flutter gives us fragment coords in pixels (origin = top-left).
    vec2 fragCoord = FlutterFragCoord().xy;

    // Normalised UV in [0, 1].
    vec2 uv = fragCoord / vec2(uWidth, uHeight);

    // ── 1. Identify the vertical strip this pixel belongs to ─────────────────
    float stripWidthNorm = STRIP_WIDTH_PX / uWidth;   // strip width in UV space
    float stripIndex     = floor(uv.x / stripWidthNorm);
    float stripFrac      = fract(uv.x / stripWidthNorm); // 0→1 within the strip
    float stripCenterX   = (stripIndex + 0.5) * stripWidthNorm;

    // ── 2. Horizontal lens refraction ────────────────────────────────────────
    // Wide pane = thick convex glass cylinder. Cubic profile gives stronger
    // pull near strip edges (creating prominent dark glass divider lines)
    // and neutral-to-slight compression at the centre.
    float lensT      = stripFrac * 2.0 - 1.0;           // -1…+1 across strip
    float lensOffset = lensT * (1.0 - lensT * lensT) * LENS_STRENGTH * uIntensity;
    float refractedX = uv.x - lensOffset * stripWidthNorm;

    // ── 3. Horizontal compression ─────────────────────────────────────────────
    // Squeeze sampled X toward the strip centre — remaps the strip's content
    // from full width to a compressed sub-region, making it look like each
    // pane shows a narrower slice of the image (tall glass pillar feel).
    // stripFrac in 0→1; offset from centre = stripFrac - 0.5 ∈ -0.5…+0.5.
    float compressOffset = (stripFrac - 0.5) * HORIZ_COMPRESS * uIntensity;
    refractedX = refractedX - compressOffset * stripWidthNorm;

    // ── 4. Sample neighbours for local contrast (edge detection) ─────────────
    // Wider sample offset (3px vs 2px) to match the coarser strip resolution
    // and capture gradients that span wider spatial frequencies.
    float dx = EDGE_SAMPLE_OFFSET / uWidth;
    float dy = EDGE_SAMPLE_OFFSET / uHeight;

    vec4 cL = sampleTex(vec2(stripCenterX - dx, uv.y));
    vec4 cR = sampleTex(vec2(stripCenterX + dx, uv.y));
    vec4 cU = sampleTex(vec2(stripCenterX,  uv.y - dy));
    vec4 cD = sampleTex(vec2(stripCenterX,  uv.y + dy));
    vec4 cC = sampleTex(vec2(stripCenterX,  uv.y));

    // Sobel-like gradient magnitude.
    float edgeH = abs(luma(cR.rgb) - luma(cL.rgb));
    float edgeV = abs(luma(cU.rgb) - luma(cD.rgb));
    float edge  = sqrt(edgeH * edgeH + edgeV * edgeV);

    // Local brightness at strip centre for this row.
    float bright = luma(cC.rgb);

    // ── 5. Vertical displacement (core wide-reed effect) ──────────────────────
    // Slower sine frequency → neighbouring strips have more similar phases,
    // producing broad, monumental columns rather than jagged narrow spikes.
    float basePhase = stripIndex * SINE_FREQ * 3.14159265;
    float baseSine  = sin(basePhase);   // -1…+1

    // Edge spike: areas with strong contrast (mountain ridges, horizon) spike up.
    float edgeSpike   = edge  * EDGE_SPIKE_MUL;

    // Brightness spike: bright content within this row rises further.
    float brightSpike = bright * BRIGHT_SPIKE_MUL;

    // Total signed vertical shift. Subtracting from y moves the sample origin
    // upward — content below "flows up" into this strip position.
    float totalShift = (baseSine + edgeSpike + brightSpike)
                       * MAX_V_SHIFT
                       * uIntensity;

    float shiftedY = uv.y - totalShift;

    // ── 6. Build final UV and clamp ───────────────────────────────────────────
    vec2 finalUV = clamp(vec2(refractedX, shiftedY), 0.0, 1.0);

    // ── 7. Output ─────────────────────────────────────────────────────────────
    fragColor = sampleTex(finalUV);
}
