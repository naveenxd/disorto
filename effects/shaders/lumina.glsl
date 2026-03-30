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
    
    // High frequency jitter to simulate vertical micro-scratches
    float noise = sin(uv.x * 400.0) * sin(uv.x * 123.0);
    float refract = noise * 0.02 * uIntensity;
    
    vec2 finalUv = clamp(vec2(uv.x, uv.y + refract), 0.0, 1.0);
    
    vec3 color = texture(uTexture, finalUv).rgb;
    // Add light streaks to the smear
    color += (noise * 0.1 * uIntensity);
    
    fragColor = vec4(color, 1.0);
}