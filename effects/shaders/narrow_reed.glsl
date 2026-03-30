// Narrow Reed — Flutter FragmentProgram shader
// Slices the image into thin vertical glass strips (~20-30px wide).
// Each strip refracts its centre content inward (lens effect), then
// displaces vertically by a sine wave whose amplitude is boosted by
// local edge contrast, producing the dramatic upward spiking seen in
// the reference screenshot.
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
// Strip width in *pixels*.  20-30 px gives the narrow-reed look.
const float STRIP_WIDTH_PX  = 24.0;

// How many pixels on either side we sample to compute local edge contrast.
const float EDGE_SAMPLE_OFFSET = 2.0;

// Maximum vertical shift (as fraction of image height) at full intensity.
const float MAX_V_SHIFT = 0.18;

// Sine wave "frequency" per strip — governs how jittery adjacent strips look.
const float SINE_FREQ = 1.1;

// Lens-refraction strength: how much the strip pinches horizontally inward.
// 0 = no refraction, 1 = extreme.
const float LENS_STRENGTH = 0.38;

// Edge-spike amplification factor on top of the base sine offset.
const float EDGE_SPIKE_MUL  = 4.5;

// Subtle brightness-driven extrusion (bright areas spike more).
const float BRIGHT_SPIKE_MUL = 1.8;

// ── Helpers ───────────────────────────────────────────────────────────────────

// Luma of a colour sample.
float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

// Sample the texture in normalised UV space.
vec4 sampleTex(vec2 uv) {
    return texture(uTexture, uv);
}

// ── Main ──────────────────────────────────────────────────────────────────────
void main() {
    // Flutter gives us fragment coords in *pixels* (origin = top-left).
    vec2 fragCoord = FlutterFragCoord().xy;

    // Normalised UV in [0, 1].
    vec2 uv = fragCoord / vec2(uWidth, uHeight);

    // ── 1. Identify the vertical strip this pixel belongs to ─────────────────
    float stripWidthNorm = STRIP_WIDTH_PX / uWidth;   // strip width in UV space
    float stripIndex     = floor(uv.x / stripWidthNorm);
    float stripFrac      = fract(uv.x / stripWidthNorm); // 0→1 within the strip
    float stripCenterX   = (stripIndex + 0.5) * stripWidthNorm;

    // ── 2. Horizontal lens refraction ────────────────────────────────────────
    // Each strip acts as a convex glass cylinder: pixels near the edges of the
    // strip are pulled toward the strip centre, compressing the image and
    // creating the characteristic bright-edge / dark refraction lines.
    // stripFrac is 0→1; remap to -1→1.
    float lensT      = stripFrac * 2.0 - 1.0;           // -1…+1 across strip
    // Cubic lens profile: stronger pull near ±1 (edges), zero at centre.
    float lensOffset = lensT * (1.0 - lensT * lensT) * LENS_STRENGTH * uIntensity;
    float refractedX = uv.x - lensOffset * stripWidthNorm;

    // ── 3. Sample neighbours for local contrast (edge detection) ─────────────
    // We sample two pixels to the left and right of the *strip centre* at the
    // same row to measure how much colour contrast is present — high contrast
    // means a strong edge and should produce a large spike.
    float dx = EDGE_SAMPLE_OFFSET / uWidth;
    float dy = EDGE_SAMPLE_OFFSET / uHeight;

    vec4 cL  = sampleTex(vec2(stripCenterX - dx, uv.y));
    vec4 cR  = sampleTex(vec2(stripCenterX + dx, uv.y));
    vec4 cU  = sampleTex(vec2(stripCenterX,  uv.y - dy));
    vec4 cD  = sampleTex(vec2(stripCenterX,  uv.y + dy));
    vec4 cC  = sampleTex(vec2(stripCenterX,  uv.y));

    // Sobel-like magnitude (horizontal + vertical gradient).
    float edgeH = abs(luma(cR.rgb) - luma(cL.rgb));
    float edgeV = abs(luma(cU.rgb) - luma(cD.rgb));
    float edge  = sqrt(edgeH * edgeH + edgeV * edgeV);

    // Local brightness at strip centre.
    float bright = luma(cC.rgb);

    // ── 4. Vertical displacement (the core reed effect) ───────────────────────
    // Base sine-wave offset per strip — adjacent strips have different phase so
    // they jitter out of sync, creating the venetian-blind shear.
    float basePhase  = stripIndex * SINE_FREQ * 3.14159265;
    float baseSine   = sin(basePhase);                        // -1…+1

    // Edge spike: contrasty areas get an additional, unsigned upward pull.
    float edgeSpike  = edge  * EDGE_SPIKE_MUL;

    // Brightness spike: brighter pixels within this row get pulled further up.
    float brightSpike = bright * BRIGHT_SPIKE_MUL;

    // Combined signed vertical shift in UV space — upward = negative because
    // UV y=0 is at the top in Flutter's coordinate space.
    float totalShift = (baseSine + edgeSpike + brightSpike)
                       * MAX_V_SHIFT
                       * uIntensity;

    // Apply: displace upward (subtract from y to move sample origin up, pulling
    // image content downward into this strip — matches the reference spike shape).
    float shiftedY = uv.y - totalShift;

    // ── 5. Build final UV and clamp to [0, 1] ────────────────────────────────
    vec2 finalUV = clamp(vec2(refractedX, shiftedY), 0.0, 1.0);

    // ── 6. Output ─────────────────────────────────────────────────────────────
    fragColor = sampleTex(finalUV);
}
