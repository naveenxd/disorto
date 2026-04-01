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
    float cellsX = 6.8;
    float cellsY = cellsX * (uHeight / uWidth);
    vec2 grid = vec2(cellsX, cellsY);
    vec2 cellUv = fract(uv * grid) - 0.5;
    vec2 cellId = floor(uv * grid);

    float radius = length(max(abs(cellUv) - vec2(0.28), 0.0));
    float tileMask = 1.0 - smoothstep(0.06, 0.12, radius);
    float bulge = (0.19 - dot(cellUv, cellUv)) * tileMask;
    vec2 offset = cellUv * bulge * 0.95 * uIntensity;

    vec2 finalUv = clamp(uv + offset / grid, 0.0, 1.0);
    vec3 color = texture(uTexture, finalUv).rgb;

    float edgeX = 1.0 - smoothstep(0.34, 0.48, abs(cellUv.x));
    float edgeY = 1.0 - smoothstep(0.34, 0.48, abs(cellUv.y));
    float seam = max(edgeX, edgeY);
    float highlight = smoothstep(-0.50, 0.10, -(cellUv.x + cellUv.y)) * seam;
    float shadow = smoothstep(-0.10, 0.55, cellUv.x + cellUv.y) * seam;

    color += highlight * 0.10 * uIntensity;
    color *= 1.0 - shadow * 0.22 * uIntensity;

    float centerGlint = pow(max(0.0, 1.0 - length(cellUv) * 2.1), 5.0);
    color += centerGlint * 0.05 * uIntensity;

    fragColor = vec4(color, 1.0);
}
