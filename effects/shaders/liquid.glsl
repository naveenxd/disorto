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

    // Wide reed — but bend the bands using uv.y so lines curve instead of straight
    float count = 10.0;
    float curve = sin(uv.y * 3.14159 * 2.0 + uTime * 0.4) * 0.08;
    float bar   = fract((uv.x + curve) * count);
    float normal = (bar - 0.5) * 2.0;
    float reed  = normal * pow(abs(normal), 1.2);

    float refractX = reed * 0.185 * uIntensity;

    vec3 blurred  = texture(uBlurTexture,  clamp(vec2(uv.x + refractX, uv.y), 0.0, 1.0)).rgb;
    vec3 original = texture(uSourceTexture, uv).rgb;

    fragColor = vec4(clamp(mix(blurred, original, clamp(uOriginalDetailWeight, 0.0, 1.0)), 0.0, 1.0), 1.0);
}