#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform sampler2D uTexture;
out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    
    // Overlapping low-frequency waves
    float w1 = sin(uv.y * 8.0 + uv.x * 2.0);
    float w2 = cos(uv.x * 10.0 + w1);
    
    vec2 refract = vec2(w1, w2) * 0.02 * uIntensity;
    vec2 finalUv = clamp(uv + refract, 0.0, 1.0);
    
    float r = texture(uTexture, finalUv + 0.005 * uIntensity).r;
    float g = texture(uTexture, finalUv).g;
    float b = texture(uTexture, finalUv - 0.005 * uIntensity).b;
    
    fragColor = vec4(r, g, b, 1.0);
}