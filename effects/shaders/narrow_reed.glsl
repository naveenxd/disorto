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
    
    float count = 50.0;
    float bar = fract(uv.x * count);
    
    // Physics: Calculate the curve of the glass rod (0 to 1 back to 0)
    float glassNormal = sin(bar * 3.14159);
    // Bending light more at the edges of the rod
    float refract = (bar - 0.5) * glassNormal * 0.04 * uIntensity;
    
    vec2 finalUv = clamp(vec2(uv.x + refract, uv.y), 0.0, 1.0);
    
    // Chromatic Aberration for high-end feel
    float r = texture(uTexture, finalUv + 0.001 * uIntensity).r;
    float g = texture(uTexture, finalUv).g;
    float b = texture(uTexture, finalUv - 0.001 * uIntensity).b;
    
    // Specular highlight at the peak of each rod
    float spec = pow(glassNormal, 10.0) * 0.1 * uIntensity;
    vec3 color = vec3(r, g, b) + spec;
    
    // Darken the valleys between rods for depth
    color *= (0.9 + 0.1 * smoothstep(0.0, 0.2, bar) * smoothstep(1.0, 0.8, bar));
    
    fragColor = vec4(color, 1.0);
}