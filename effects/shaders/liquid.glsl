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

    // Horizontal displacement ONLY — overlapping low-frequency sine waves.
    // Wave 1: higher frequency, full strength
    float w1 = sin(uv.y * 12.0) * 0.04 * uIntensity;
    // Wave 2: lower frequency, phase-shifted, softer
    float w2 = sin(uv.y * 7.0 + 1.5) * 0.025 * uIntensity;

    // Only X is displaced — pure horizontal liquid shear
    vec2 finalUv = clamp(vec2(uv.x + w1 + w2, uv.y), 0.0, 1.0);

    fragColor = vec4(texture(uTexture, finalUv).rgb, 1.0);
}