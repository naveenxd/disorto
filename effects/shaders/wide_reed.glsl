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
    uv.x += sin(uv.y * 4.6 + uTime * 0.8) * 0.012 * uIntensity;
    float noise = sin(uv.y * 80.0 + uv.x * 40.0 + uTime) * 0.002;
    uv.x += noise;

    float count = 16.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float center = 1.0 - abs(normal);
    float mask = pow(max(center, 0.0), 2.0);

    float refractX = (normal * abs(normal) * 0.040 + sin(uv.y * 12.0 + uTime * 1.5) * 0.006) * uIntensity;
    float refractY = (sin(floor(uv.x * count) * 0.7 + uTime * 0.7) * 0.0045) * uIntensity;

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(
        uBlurTexture,
        clamp(vec2(uv.x + refractX, uv.y + refractY), 0.0, 1.0)
    ).rgb;

    float seam = 1.0 - smoothstep(0.38, 0.50, abs(normal));
    vec3 color = mix(base, glass, clamp((0.34 + 0.24 * mask) * uIntensity, 0.0, 0.64));
    color += mask * 0.065 * uIntensity;
    color *= 1.0 - seam * 0.10 * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
