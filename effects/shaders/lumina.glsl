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
    uv.x += sin(uv.y * 5.0 + uTime * 0.6) * 0.012 * uIntensity;
    float noise = fract(sin(dot((uv + vec2(uTime * 0.008, uTime * 0.011)) * 100.0, vec2(12.9898, 78.233))) * 43758.5453);
    uv += (noise - 0.5) * 0.002;

    float count = 10.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float mask = pow(max(1.0 - abs(normal), 0.0), 4.0);
    float rise = pow(uv.y, 1.6);

    vec2 refractedUv = clamp(
        vec2(
            uv.x + sin(uv.y * 9.0 + uTime * 1.1) * 0.016 * uIntensity,
            uv.y - mask * rise * 0.048 * uIntensity
        ),
        0.0,
        1.0
    );

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(base, glass, clamp((0.32 + 0.28 * mask * rise) * uIntensity, 0.0, 0.60));
    color += mask * 0.075 * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
