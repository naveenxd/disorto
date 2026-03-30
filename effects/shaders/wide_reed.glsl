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
    
    float count = 18.0;
    float bar = fract(uv.x * count);
    
    // Wider glass profile
    float glassNormal = pow(sin(bar * 3.14159), 0.5);
    float refract = (bar - 0.5) * (1.0 - glassNormal) * 0.06 * uIntensity;
    
    vec2 finalUv = clamp(vec2(uv.x + refract, uv.y), 0.0, 1.0);
    
    float r = texture(uTexture, finalUv + 0.002 * uIntensity).r;
    float g = texture(uTexture, finalUv).g;
    float b = texture(uTexture, finalUv - 0.002 * uIntensity).b;
    
    // Shadowing the joints between panels
    float shadow = smoothstep(0.0, 0.1, bar) * smoothstep(1.0, 0.9, bar);
    vec3 color = vec3(r, g, b) * (0.85 + 0.15 * shadow);
    
    fragColor = vec4(color, 1.0);
}