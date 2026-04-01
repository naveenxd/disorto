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

    // 15 wider vertical glass rods
    const float count = 15.0;
    float strip = floor(uv.x * count);
    float bar   = fract(uv.x * count);

    // Glass-rod lens curve
    float lensCurve = sin(bar * 3.14159265);

    // Stronger X refraction than narrow reed (~0.04 max)
    float refractX = (bar - 0.5) * lensCurve * 0.08 * uIntensity;

    // Vertical offset per strip — each rod shifts Y slightly differently
    // giving a subtle "offset pane" look visible in wide_reed reference
    float refractY = sin(strip * 1.37) * 0.018 * uIntensity;

    vec2 finalUv = clamp(vec2(uv.x + refractX, uv.y + refractY), 0.0, 1.0);

    vec3 color = texture(uTexture, finalUv).rgb;

    // Specular highlight
    float spec = pow(lensCurve, 6.0) * 0.1 * uIntensity;
    color += spec;

    // Dark divider seam between rods
    float seam = smoothstep(0.0, 0.07, bar) * smoothstep(1.0, 0.93, bar);
    color *= mix(1.0, 0.88 + 0.12 * seam, uIntensity);

    fragColor = vec4(color, 1.0);
}