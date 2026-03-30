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
    float aspect = uWidth / uHeight;
    vec2 center = vec2(0.5, 0.5);
    
    vec2 dir = uv - center;
    dir.y /= aspect;
    float dist = length(dir);
    
    // Physics: Wave refraction slope
    float wave = cos(dist * 30.0) * 0.04 * uIntensity;
    wave *= exp(-dist * 1.5); // Decay
    
    vec2 finalUv = clamp(uv + normalize(uv - center) * wave, 0.0, 1.0);
    
    float r = texture(uTexture, finalUv + 0.004 * uIntensity).r;
    float g = texture(uTexture, finalUv).g;
    float b = texture(uTexture, finalUv - 0.004 * uIntensity).b;
    
    fragColor = vec4(r, g, b, 1.0);
}