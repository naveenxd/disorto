// Ripple — Flutter FragmentProgram shader
// Radial concentric ripple waves emanating from a focal point, combined with
// a strong inward swirl rotation that peaks at the centre and decays toward
// the edges. The result: gentle ring waves in the outer fringe, dramatic
// spiral vortex in the core.
//
// Visual character (from reference screenshot):
//   • Focal point is slightly above image centre (~40% down), not dead centre.
//   • Outer region: clean, evenly-spaced elliptical ripple rings, low swirl.
//   • Inner region: extreme spiral wrap (~270°), ripple rings still visible.
//   • Swirl angle ∝ (1 - dist²): maximum at focal point, zero at far edge.
//   • Ripple sine amplitude is bell-shaped in dist: peaks at mid-range,
//     fades toward both the far edge and the very centre (matching the calm
//     eye of the vortex in the reference).
//   • A subtle radial lens squeeze (fisheye) pulls the focal-area content
//     inward, making the core look slightly zoomed-in / compressed.
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

// Focal point in normalised UV — slightly above vertical centre per reference.
const vec2  FOCAL_UV       = vec2(0.5, 0.42);

// ── Ripple wave ───────────────────────────────────────────────────────────────
// Spatial frequency of the concentric rings (cycles per unit radius, where
// the full diagonal is ~1.4 units). 22 gives ~8-10 visible rings per frame.
const float RIPPLE_FREQ    = 22.0;

// Maximum radial displacement from the ripple sine wave (fraction of the
// image short edge). 0.032 ≈ ~3% of width → tight, sharp ring displacement.
const float RIPPLE_AMP     = 0.032;

// Bell curve width for the ripple amplitude envelope.
// Ripple is strongest at dist ≈ RIPPLE_PEAK, fades inward and outward.
const float RIPPLE_PEAK    = 0.38;   // distance (UV) of max ring amplitude
const float RIPPLE_BELL_W  = 0.28;   // Gaussian sigma of the bell envelope

// ── Swirl rotation ────────────────────────────────────────────────────────────
// Maximum swirl angle at the focal point (radians). π × 1.5 ≈ 270°.
const float SWIRL_MAX_ANGLE = 4.71238898;  // 1.5 * π

// Swirl fall-off: uses (1 - dist²) profile so the outer fringe swirls very
// little while the inner core is heavily spun. Exponent 1.6 gives a steeper
// boundary between the calm outer rings and the turbulent core.
const float SWIRL_FALLOFF_EXP = 1.6;

// Radius beyond which swirl is essentially zero (UV distance from focal).
// The reference shows clean rings up in the sky corners → keep swirl tight.
const float SWIRL_RADIUS   = 0.72;

// ── Radial lens (fisheye compression at core) ─────────────────────────────────
// Pulls sample radius inward at the centre, magnifying the core content.
// 0 = no lens, 1 = strong. 0.18 gives the mild but visible zoom seen in ref.
const float LENS_STRENGTH  = 0.18;

// ── Helpers ───────────────────────────────────────────────────────────────────

vec4 sampleTex(vec2 uv) {
    return texture(uTexture, uv);
}

// ── Main ──────────────────────────────────────────────────────────────────────
void main() {
    // Flutter gives us fragment coords in pixels (origin = top-left).
    vec2 fragCoord = FlutterFragCoord().xy;

    // Normalised UV in [0, 1].
    vec2 uv = fragCoord / vec2(uWidth, uHeight);

    // ── 1. Compute polar coordinates from focal point ─────────────────────────
    // We correct for aspect ratio so "dist" is a true geometric distance, not
    // squashed by the portrait aspect. This makes the ripple rings elliptical
    // on the screen (matching the reference — wider than tall) rather than
    // perfectly circular.
    float aspect  = uWidth / uHeight;
    vec2  delta   = uv - FOCAL_UV;
    vec2  deltaAR = vec2(delta.x * aspect, delta.y);  // aspect-corrected
    float dist    = length(deltaAR);                   // true distance
    float angle   = atan(delta.y, delta.x);            // polar angle (full 2π)

    // ── 2. Swirl rotation ─────────────────────────────────────────────────────
    // Rotation angle decays from SWIRL_MAX_ANGLE at dist=0 to 0 at SWIRL_RADIUS.
    // Clamp dist so pixels outside SWIRL_RADIUS get zero swirl.
    float distNorm  = clamp(dist / SWIRL_RADIUS, 0.0, 1.0);
    float swirlFrac = 1.0 - pow(distNorm, SWIRL_FALLOFF_EXP); // 1 at centre → 0 at edge
    float swirlAngle = SWIRL_MAX_ANGLE * swirlFrac * uIntensity;

    // Rotate the *sample* polar angle by -swirlAngle (opposite to perceived
    // rotation direction so the content appears to spin inward/anti-clockwise).
    float sampledAngle = angle - swirlAngle;

    // ── 3. Radial ripple displacement ─────────────────────────────────────────
    // A sine wave along the radial distance creates concentric rings.
    float rippleSine = sin(dist * RIPPLE_FREQ * 6.28318530);

    // Bell-shaped amplitude envelope: strong at mid-range, weak at extremes.
    float bellDist   = dist - RIPPLE_PEAK;
    float bellEnv    = exp(-(bellDist * bellDist) / (2.0 * RIPPLE_BELL_W * RIPPLE_BELL_W));

    // The ripple nudges the sampling radius outward or inward along radial dir.
    float rippleDisp = rippleSine * bellEnv * RIPPLE_AMP * uIntensity;

    // ── 4. Radial lens (fisheye at core) ──────────────────────────────────────
    // Pull the sampled radius inward proportional to (1 - dist) — magnifies
    // content near the focal point, matches the spherical ball look in ref.
    float lensDisp   = -dist * (1.0 - distNorm) * LENS_STRENGTH * uIntensity;

    // Final sampled radius.
    float sampledDist = dist + rippleDisp + lensDisp;

    // ── 5. Reconstruct sampled UV from polar coordinates ─────────────────────
    // Convert back from aspect-corrected polar to UV space.
    // sampledAngle and sampledDist are in the AR-corrected coordinate system,
    // so we divide x by aspect when converting back.
    vec2 sampleDelta = vec2(
        cos(sampledAngle) * sampledDist / aspect,
        sin(sampledAngle) * sampledDist
    );
    vec2 sampleUV = FOCAL_UV + sampleDelta;

    // ── 6. Clamp and output ───────────────────────────────────────────────────
    vec2 finalUV = clamp(sampleUV, 0.0, 1.0);
    fragColor    = sampleTex(finalUV);
}
