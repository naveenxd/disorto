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

    float weight = 0.32 + 0.68 * pow(uv.y, 1.25);
    float wave1 = sin(uv.y * 6.0 + uv.x * 3.0);
    float wave2 = sin(uv.y * 10.5 - uv.x * 1.8);
    float wave3 = sin(uv.y * 16.0 + uv.x * 0.6);

    vec2 refractedUv = clamp(
        uv + vec2(
            (wave1 * 0.022 + wave2 * 0.012 + wave3 * 0.006) * weight * uIntensity,
            (wave2 * 0.004 + wave3 * 0.002) * weight * uIntensity
        ),
        0.0,
        1.0
    );

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(base, glass, (0.16 + 0.22 * weight) * uIntensity);
    color += 0.035 * weight * uIntensity;

    fragColor = vec4(color, 1.0);
}
