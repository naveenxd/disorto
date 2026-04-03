#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform sampler2D uSourceTexture;
uniform sampler2D uBlurTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    float cellsX = 6.0;
    float cellsY = cellsX * (uHeight / uWidth);
    vec2 grid = vec2(cellsX, cellsY);
    vec2 gv = fract(uv * grid) - 0.5;

    vec2 rounded = abs(gv) - vec2(0.26);
    float radius = length(max(rounded, 0.0));
    float tile = 1.0 - smoothstep(0.04, 0.11, radius);

    vec2 refractedUv = clamp(
        uv + (gv * 0.010 * tile) / grid * uIntensity,
        0.0,
        1.0
    );

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(base, glass, tile * 0.16 * uIntensity);

    float seamX = 1.0 - smoothstep(0.35, 0.48, abs(gv.x));
    float seamY = 1.0 - smoothstep(0.35, 0.48, abs(gv.y));
    float seam = max(seamX, seamY);
    color += seam * 0.05 * uIntensity;
    color *= 1.0 - seam * 0.08 * uIntensity;

    fragColor = vec4(color, 1.0);
}
