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

    // Cell size ~60px in UV space
    vec2 cellSize = vec2(60.0 / uWidth, 60.0 / uHeight);

    // Which cell we're in and where within it (0→1)
    vec2 cellIndex = floor(uv / cellSize);
    vec2 cellUV    = fract(uv / cellSize);  // 0→1 within the cell

    // Offset from cell centre (−0.5 → +0.5)
    vec2 offset = cellUV - vec2(0.5);
    float dist  = length(offset);

    // Convex lens: push pixels outward radially from cell centre.
    // The closer to centre, the more they're pushed out (inward fetch = outward push).
    float lensStrength = uIntensity * 0.35;
    vec2 lensOffset = offset * (1.0 - dist * 1.8) * lensStrength;

    vec2 finalUv = clamp(uv + lensOffset, 0.0, 1.0);

    vec3 color = texture(uTexture, finalUv).rgb;

    // Thin dark border at cell edges using min of distances to all 4 edges
    float edgeDist = min(min(cellUV.x, 1.0 - cellUV.x),
                         min(cellUV.y, 1.0 - cellUV.y));
    float border = 1.0 - smoothstep(0.0, 0.06, edgeDist);
    color = mix(color, color * 0.35, border * uIntensity);

    // Subtle specular glint in the centre of each lens
    float spec = pow(max(0.0, 1.0 - dist * 3.0), 6.0) * 0.12 * uIntensity;
    color += spec;

    fragColor = vec4(color, 1.0);
}