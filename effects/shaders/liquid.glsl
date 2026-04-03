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
    uv.x += sin(uv.y * 6.0 + uTime * 1.0) * 0.015 * uIntensity;
    float noise = fract(sin(dot((uv + vec2(uTime * 0.012, uTime * 0.01)) * 100.0, vec2(12.9898, 78.233))) * 43758.5453);
    uv += (noise - 0.5) * 0.002;

    float weight = 0.32 + 0.68 * pow(uv.y, 1.25);
    float wave1 = sin(uv.y * 5.2 + uv.x * 2.5 + uTime * 1.1);
    float wave2 = sin(uv.y * 8.8 - uv.x * 1.6 - uTime * 1.5);
    float wave3 = sin(uv.y * 13.2 + uv.x * 0.8 + uTime * 1.9);

    vec2 refractedUv = clamp(
        uv + vec2(
            (wave1 * 0.060 + wave2 * 0.034 + wave3 * 0.020) * weight * uIntensity,
            (wave2 * 0.014 + wave3 * 0.008) * weight * uIntensity
        ),
        0.0,
        1.0
    );

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(glass, base, clamp(uOriginalDetailWeight, 0.0, 1.0));
    color += 0.070 * weight * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
