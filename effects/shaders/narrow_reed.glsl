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
    float count = 36.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float center = 1.0 - abs(normal);
    float mask = pow(max(center, 0.0), 2.8);

    float refract = normal * abs(normal) * 0.016 * uIntensity;

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(
        uBlurTexture,
        clamp(vec2(uv.x + refract, uv.y), 0.0, 1.0)
    ).rgb;

    float seam = 1.0 - smoothstep(0.42, 0.50, abs(normal));
    vec3 color = mix(base, glass, (0.08 + 0.12 * mask) * uIntensity);
    color += mask * 0.035 * uIntensity;
    color *= 1.0 - seam * 0.06 * uIntensity;

    fragColor = vec4(color, 1.0);
}
