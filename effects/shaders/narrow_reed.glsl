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
    uv.x += sin(uv.y * 6.0 + uTime * 0.9) * 0.015 * uIntensity;
    float noise = fract(sin(dot((uv + vec2(uTime * 0.01, uTime * 0.015)) * 100.0, vec2(12.9898, 78.233))) * 43758.5453);
    uv += (noise - 0.5) * 0.002;

    float count = 36.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float center = 1.0 - abs(normal);
    float mask = pow(max(center, 0.0), 2.8);

    float wobble = sin(uv.y * 14.0 + uTime * 1.7) * 0.010;
    float refract = (normal * abs(normal) * 0.052 + wobble) * uIntensity;

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(
        uBlurTexture,
        clamp(vec2(uv.x + refract, uv.y), 0.0, 1.0)
    ).rgb;

    float seam = 1.0 - smoothstep(0.40, 0.50, abs(normal));
    float edge = smoothstep(0.25, 0.0, abs(normal));
    vec3 color = mix(base, glass, clamp((0.34 + 0.30 * mask) * uIntensity, 0.0, 0.64));
    color += mask * 0.070 * uIntensity + edge * 0.05 * uIntensity;
    color *= 1.0 - seam * 0.12 * uIntensity;
    color *= 1.0 - edge * 0.05 * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
