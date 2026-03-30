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
    vec2 gridCount = vec2(10.0, 10.0 / aspect);
    
    vec2 tileUv = fract(uv * gridCount);
    
    // Calculate distance to center for the "Lens" effect
    vec2 p = (tileUv - 0.5) * 2.0;
    float d = dot(p, p);
    float refract = d * 0.05 * uIntensity;
    
    vec2 finalUv = clamp(uv + (p * refract * 0.1), 0.0, 1.0);
    
    // Create the "Bezel" (shading the tile edges)
    float bezel = smoothstep(0.4, 0.5, abs(tileUv.x - 0.5)) + 
                  smoothstep(0.4, 0.5, abs(tileUv.y - 0.5));
    
    float r = texture(uTexture, finalUv + 0.003 * uIntensity).r;
    float g = texture(uTexture, finalUv).g;
    float b = texture(uTexture, finalUv - 0.003 * uIntensity).b;
    
    vec3 color = vec3(r, g, b);
    color = mix(color, color * 0.6, bezel * 0.5 * uIntensity);
    
    fragColor = vec4(color, 1.0);
}