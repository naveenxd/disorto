// Liquid — Flutter FragmentProgram shader
// Horizontal sine-wave displacement that varies per row, creating a marble /
// flowing-water effect. Displacement grows stronger toward the bottom of the
// image, with multiple layered sine frequencies for organic complexity.
//
// Visual character (from reference screenshot):
//   • Top (sky, ~20%) is nearly undistorted — gentle vertical streaks only.
//   • Mid-section transitions into wide flowing horizontal wave curves.
//   • Bottom is heavily distorted: dense layered marble / agate-stone bands.
//   • Two sine frequencies: slow wide-amplitude + fast tight-ribbon wave.
//   • Cross-axis (vertical) undulation adds flowing 3D-terrain illusion.
//   • Wave phase offset varies with x so bands curve, not lying flat horizontal.
//   • Y-displacement ramp is non-linear (cubic) — near zero at top, maximum
//     at bottom. Amplitude grows fast in the lower third.
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

// ── Wave 1: Slow / wide-amplitude (the large flowing curves) ─────────────────
// Spatial frequency of the slow wave in y (cycles per image height).
const float W1_FREQ_Y     = 6.0;
// How much the wave phase shifts per unit x — makes bands curve rather than
// lying flat. Higher = more curved / sinuous bands.
const float W1_PHASE_X    = 5.0;
// Maximum horizontal shift (fraction of image width) at full intensity, bottom.
const float W1_AMP_X      = 0.09;
// Max vertical shift (fraction of image height) from wave 1.
const float W1_AMP_Y      = 0.025;

// ── Wave 2: Fast / tight-ribbon wave (the marble / agate detail) ─────────────
const float W2_FREQ_Y     = 18.0;
const float W2_PHASE_X    = 8.5;
const float W2_AMP_X      = 0.038;
const float W2_AMP_Y      = 0.012;

// ── Wave 3: Very slow drift wave (big background undulation) ─────────────────
// Gives the large-scale flowing curvature visible across the full image.
const float W3_FREQ_Y     = 2.5;
const float W3_PHASE_X    = 2.2;
const float W3_AMP_X      = 0.055;

// ── Y-ramp ────────────────────────────────────────────────────────────────────
// Exponent of the power-law ramp from top→bottom. 3 = cubic: near-zero for
// the top third, then accelerates strongly into the bottom third.
const float Y_RAMP_EXP    = 3.0;

// Extra linear boost that preserves a small minimum displacement at the top
// (the faint vertical-streak artefacts visible in the sky).
const float Y_RAMP_FLOOR  = 0.04;

// ── Vertical smear from horizontal gradient ───────────────────────────────────
// Adds a gentle vertical displacement driven by the local horizontal brightness
// gradient — this is what creates the "flowing terrain" 3D illusion vs flat
// horizontal bands.
const float CROSS_GRAD_MUL = 0.6;
const float CROSS_SAMPLE_DX = 2.0;  // pixels

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

    // Normalised UV in [0, 1]. y = 0 at top, y = 1 at bottom.
    vec2 uv = fragCoord / vec2(uWidth, uHeight);

    // ── 1. Y-ramp: displacement grows toward bottom ───────────────────────────
    // Cubic with a small floor so the very top still shows faint streaks.
    float yRamp = Y_RAMP_FLOOR + (1.0 - Y_RAMP_FLOOR) * pow(uv.y, Y_RAMP_EXP);

    // ── 2. Compute the three layered sine displacements ───────────────────────
    // Each wave uses uv.y as the primary frequency driver and adds a phase term
    // in uv.x so horizontal bands curve rather than lying flat.
    float pi2 = 6.28318530;

    // Wave 1 — slow / large curves
    float w1Phase = uv.y * W1_FREQ_Y * pi2 + uv.x * W1_PHASE_X * pi2;
    float w1X     = sin(w1Phase)    * W1_AMP_X;
    float w1Y     = cos(w1Phase * 0.7 + 1.1) * W1_AMP_Y;  // de-phase Y slightly

    // Wave 2 — fast / tight ripple (marble ribbon detail)
    float w2Phase = uv.y * W2_FREQ_Y * pi2 + uv.x * W2_PHASE_X * pi2 + 0.8;
    float w2X     = sin(w2Phase)    * W2_AMP_X;
    float w2Y     = cos(w2Phase * 0.5 + 2.3) * W2_AMP_Y;

    // Wave 3 — very slow drift
    float w3Phase = uv.y * W3_FREQ_Y * pi2 + uv.x * W3_PHASE_X * pi2 + 3.7;
    float w3X     = sin(w3Phase)    * W3_AMP_X;
    // Wave 3 contributes only horizontal (it's the global slosh)

    // Total combined displacement before intensity + ramp.
    float totalDX = w1X + w2X + w3X;
    float totalDY = w1Y + w2Y;

    // ── 3. Local horizontal brightness gradient → vertical smear ─────────────
    // Sample two pixels left/right to get the horizontal luma gradient.
    // This gradient, when added to the vertical displacement, makes the flowing
    // "3D terrain" curves instead of flat horizontal stripes.
    float dx    = CROSS_SAMPLE_DX / uWidth;
    float lumaL = luma(sampleTex(vec2(max(uv.x - dx, 0.0), uv.y)).rgb);
    float lumaR = luma(sampleTex(vec2(min(uv.x + dx, 1.0), uv.y)).rgb);
    float horizGrad = lumaR - lumaL;    // signed: negative = brighter on left

    // The gradient-driven vertical nudge: bright-to-dark transitions pull the
    // sample slightly upward; dark-to-bright pull slightly downward — this is
    // what makes the marble bands wrap around the terrain shape.
    float crossY = horizGrad * CROSS_GRAD_MUL * 0.04;

    // ── 4. Scale by intensity and y-ramp ─────────────────────────────────────
    float scaledDX = totalDX * yRamp * uIntensity;
    float scaledDY = (totalDY + crossY) * yRamp * uIntensity;

    // ── 5. Apply displacement ─────────────────────────────────────────────────
    // Positive DX shifts pixels rightward; negative shifts left.
    // We add to UV so the sample origin moves — the perceived content shifts
    // in the opposite direction.
    vec2 displacedUV = uv + vec2(scaledDX, scaledDY);

    // ── 6. Clamp and output ───────────────────────────────────────────────────
    vec2 finalUV = clamp(displacedUV, 0.0, 1.0);
    fragColor    = sampleTex(finalUV);
}
