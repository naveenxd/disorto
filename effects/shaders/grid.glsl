#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform float uTime;
uniform float uOriginalDetailWeight;
uniform sampler2D uSourceTexture;
uniform sampler2D uBlurTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    float noise = fract(sin(dot((uv + vec2(uTime * 0.012, uTime * 0.009)) * 100.0, vec2(12.9898, 78.233))) * 43758.5453);
    uv += (noise - 0.5) * 0.002;

    float aspect = uWidth / uHeight;
    float cellsX = 6.0;
    float cellsY = cellsX / aspect;
    vec2 grid = vec2(cellsX, cellsY);
    vec2 gv = fract(uv * grid) - 0.5;

    vec2 rounded = abs(gv) - vec2(0.25);
    float radius = length(max(rounded, 0.0));
    float tile = 1.0 - smoothstep(0.03, 0.10, radius);
    float bulge = max(0.0, 1.0 - dot(gv, gv) * 3.6);

    vec2 refractedUv = clamp(
        uv + (gv * 0.062 * tile) / grid * uIntensity
           + vec2(
               sin(uv.y * 10.0 + uTime * 1.2) * 0.006,
               cos(uv.x * 8.0 + uTime * 0.9) * 0.005
             ) * (tile + bulge * 0.6) * uIntensity,
        0.0,
        1.0
    );

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(glass, base, clamp(uOriginalDetailWeight, 0.0, 1.0));

    float seamX = 1.0 - smoothstep(0.34, 0.48, abs(gv.x));
    float seamY = 1.0 - smoothstep(0.34, 0.48, abs(gv.y));
    float seam = max(seamX, seamY);
    float edge = smoothstep(0.25, 0.0, radius);
    color += seam * 0.11 * uIntensity + edge * 0.07 * uIntensity;
    color *= 1.0 - seam * 0.14 * uIntensity;
    color *= 1.0 - edge * 0.06 * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
