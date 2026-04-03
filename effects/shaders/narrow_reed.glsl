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
    float count = 32.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float reed = normal * pow(abs(normal), 1.3);
    float refractX = reed * 0.135 * uIntensity;

    vec3 blurred = texture(
        uBlurTexture,
        clamp(vec2(uv.x + refractX, uv.y), 0.0, 1.0)
    ).rgb;
    vec3 original = texture(uSourceTexture, uv).rgb;
    vec3 color = mix(blurred, original, clamp(uOriginalDetailWeight, 0.0, 1.0));

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
