// Lumina — Flutter FragmentProgram shader
// Pixels are displaced *downward* (smeared toward the bottom) based on local
// brightness and vertical edge strength, producing the crystalline "light-drip"
// extrusion seen in the reference screenshot.
//
// Visual character (from reference):
//   • Upper image (~top 40%) is largely intact — effect grows with y.
//   • Bright and high-contrast areas smear into long downward vertical trails.
//   • Thin dark streaks run between bright columns, like light refracting
//     through a faceted crystal surface.
//   • The drip becomes increasingly dramatic toward the bottom of the image.
//
// The context snippet displaces uv.y -= spike * (1 - uv.y), which pulls pixels
// upward (moves the sample origin up, dragging image content downward visually).
// We extend this with per-column edge detection and column-coherent noise so
// the streaks stay spatially consistent without introducing banding.
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

// How far upward the sample origin is shifted at full brightness + full
// intensity at the very bottom of the image. 0.45 = 45% of image height.
const float MAX_SPIKE        = 0.45;

// Brightness lift multiplier — contributes to the base upward pull.
const float BRIGHT_MUL       = 1.0;

// Edge contribution — vertical edges add to the spike, creating the thin
// sharp streaks visible between rock facets.
const float EDGE_MUL         = 2.2;

// Horizontal sample offset in pixels for the edge gradient probe.
const float EDGE_DX          = 1.5;

// Vertical sample offset in pixels for the brightness look-ahead.
// Sampling slightly *above* the current pixel for the brightness driver means
// the drip "anticipates" bright content above — matching how light trails
// appear to flow downward from a bright source.
const float BRIGHT_SAMPLE_DY = 4.0;

// The y-exponent controls how steeply distortion ramps up toward the bottom.
// exponent 2 = quadratic ramp (gentle at top, steep at bottom).
const float Y_RAMP_EXP       = 2.0;

// Thin vertical column-phase modulation: a low-frequency sine across x
// creates subtle lateral variation in streak density (matches the slight
// waviness between streaks in the reference).
const float COL_MODULATE_AMP  = 0.18;
const float COL_MODULATE_FREQ = 14.0;  // cycles across image width

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

    // ── 1. Y-ramp: distortion grows quadratically toward the bottom ───────────
    // At uv.y = 0 (top)    → ramp ≈ 0  → image mostly undistorted.
    // At uv.y = 1 (bottom) → ramp = 1  → full spike displacement.
    float yRamp = pow(uv.y, Y_RAMP_EXP);

    // ── 2. Sample brightness slightly above current row ───────────────────────
    // Sampling a few pixels above means bright regions above "flow down" into
    // the current pixel, producing the downward light-trail behaviour.
    float sampleDY = BRIGHT_SAMPLE_DY / uHeight;
    vec4  cAbove   = sampleTex(vec2(uv.x, max(uv.y - sampleDY, 0.0)));
    float bright   = luma(cAbove.rgb);

    // ── 3. Horizontal edge detection at current position ──────────────────────
    // Thin vertical streaks appear where horizontal brightness gradient is high
    // (i.e. at the boundary between bright lit rock faces and dark shadow).
    float dx = EDGE_DX / uWidth;
    float lumaL = luma(sampleTex(vec2(max(uv.x - dx, 0.0), uv.y)).rgb);
    float lumaR = luma(sampleTex(vec2(min(uv.x + dx, 1.0), uv.y)).rgb);
    float edgeH = abs(lumaR - lumaL);   // horizontal gradient → vertical edge

    // ── 4. Column-coherent lateral modulation ────────────────────────────────
    // A slow sine across x makes adjacent streaks slightly thicker/thinner,
    // preventing the uniform-grid look and adding organic crystal variation.
    float colMod = 1.0 + COL_MODULATE_AMP
                        * sin(uv.x * COL_MODULATE_FREQ * 3.14159265);

    // ── 5. Compute total spike (upward sample displacement) ───────────────────
    // spike > 0 → sample origin moves up → image content appears to drip down.
    float spike = (bright * BRIGHT_MUL + edgeH * EDGE_MUL)
                  * colMod
                  * yRamp
                  * MAX_SPIKE
                  * uIntensity;

    // ── 6. Apply displacement ─────────────────────────────────────────────────
    // Subtract spike from y: pulls the sample origin upward, smearing content
    // that was above into the current pixel → downward drip illusion.
    float shiftedY = uv.y - spike;

    // ── 7. Subtle horizontal shimmer at streak edges ──────────────────────────
    // A tiny horizontal nudge proportional to edgeH gives the impression of
    // light bending laterally through the crystal facets (visible as very faint
    // horizontal colour shifts at streak boundaries in the reference).
    float shimmerX = edgeH * yRamp * uIntensity * 0.018
                           * sign(lumaR - lumaL);
    float shiftedX = uv.x + shimmerX;

    // ── 8. Clamp and output ───────────────────────────────────────────────────
    vec2 finalUV = clamp(vec2(shiftedX, shiftedY), 0.0, 1.0);
    fragColor = sampleTex(finalUV);
}
