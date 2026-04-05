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
    float aspect = uWidth / uHeight;

    vec2 center = vec2(0.5, 0.5);
    vec2 delta  = (uv - center) * vec2(aspect, 1.0);
    float dist  = length(delta);
    float angle = atan(delta.y, delta.x);

    float ripple = sin(dist * 30.0 - uTime * 4.0);
    float newDist = dist + ripple * 0.05 * uIntensity;

    vec2 warpedUV = center + vec2(cos(angle) / aspect, sin(angle)) * newDist;
    warpedUV = clamp(warpedUV, 0.0, 1.0);

    vec3 blurred  = texture(uBlurTexture,  warpedUV).rgb;
    vec3 original = texture(uSourceTexture, warpedUV).rgb;

    fragColor = vec4(clamp(mix(blurred, original, clamp(uOriginalDetailWeight, 0.0, 1.0)), 0.0, 1.0), 1.0);
}