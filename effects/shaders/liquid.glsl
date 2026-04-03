#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform float uTime;
uniform sampler2D uSourceTexture;
uniform sampler2D uBlurTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    uv.x += sin(uv.y * 6.0 + uTime * 1.0) * 0.010 * uIntensity;
    float noise = sin(uv.y * 80.0 + uv.x * 40.0 + uTime * 1.4) * 0.002;
    uv.x += noise;

    float weight = 0.32 + 0.68 * pow(uv.y, 1.25);
    float wave1 = sin(uv.y * 6.0 + uv.x * 3.0 + uTime * 1.3);
    float wave2 = sin(uv.y * 10.5 - uv.x * 1.8 - uTime * 1.7);
    float wave3 = sin(uv.y * 16.0 + uv.x * 0.6 + uTime * 2.2);

    vec2 refractedUv = clamp(
        uv + vec2(
            (wave1 * 0.042 + wave2 * 0.024 + wave3 * 0.012) * weight * uIntensity,
            (wave2 * 0.010 + wave3 * 0.005) * weight * uIntensity
        ),
        0.0,
        1.0
    );

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(base, glass, clamp((0.34 + 0.28 * weight) * uIntensity, 0.0, 0.68));
    color += 0.055 * weight * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
