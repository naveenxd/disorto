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
    
    // Create horizontal bands with wavy distortion
    float count = 12.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float reed = normal * pow(abs(normal), 1.2);
    
    // Add wave animation to make lines wavy instead of straight
    float wave = sin(uv.y * 8.0 + uTime * 0.8) * 0.3;
    float wave2 = sin(uv.x * 3.0 - uTime * 0.6) * 0.2;
    
    // Combine reed distortion with wave animation
    float refractX = (reed + wave + wave2) * 0.185 * uIntensity;
    
    // Sample textures with refracted coordinates
    vec3 blurred = texture(
        uBlurTexture,
        clamp(vec2(uv.x + refractX, uv.y), 0.0, 1.0)
    ).rgb;
    vec3 original = texture(uSourceTexture, uv).rgb;
    vec3 color = mix(blurred, original, clamp(uOriginalDetailWeight, 0.0, 1.0));

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
