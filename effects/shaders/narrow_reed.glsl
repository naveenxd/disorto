#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform sampler2D uTexture;
out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);

    // 50 vertical glass rods
    const float count = 50.0;
    float strip = floor(uv.x * count);
    float bar   = fract(uv.x * count);  // 0→1 within each rod

    // Glass-rod lens curve: sin(bar*PI) peaks at bar=0.5 (centre of rod)
    float lensCurve = sin(bar * 3.14159265);

    // Horizontal-only refraction: push pixels toward/away from rod centre.
    // (bar - 0.5) gives direction; lensCurve gives magnitude.
    // Max displacement ≈ 0.5 * 0.02 * 2 = 0.02 UV units (subtle, as requested)
    float refractX = (bar - 0.5) * lensCurve * 0.04 * uIntensity;

    // NO Y displacement — vertical rods only displace X
    vec2 finalUv = clamp(vec2(uv.x + refractX, uv.y), 0.0, 1.0);

    vec3 color = texture(uTexture, finalUv).rgb;

    // Specular highlight at the crown of each rod (where lensCurve peaks)
    float spec = pow(lensCurve, 8.0) * 0.08 * uIntensity;
    color += spec;

    // Thin dark groove between rods: darken near the joint (bar≈0 or bar≈1)
    float groove = smoothstep(0.0, 0.06, bar) * smoothstep(1.0, 0.94, bar);
    color *= mix(1.0, 0.92 + 0.08 * groove, uIntensity);

    fragColor = vec4(color, 1.0);
}