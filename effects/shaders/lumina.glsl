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
    // Straight thin strips
    float count = 10.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    // Very high power = extremely thin sharp lines
    float mask = pow(max(1.0 - abs(normal), 0.0), 50.0);
    
    // Wider visible strip area with sharp core
    float stripWidth = 1;
    float stripInfluence = smoothstep(stripWidth, 0.0, abs(normal));
    
    vec2 refractedUv = clamp(
        vec2(
            uv.x,
            uv.y - mask * 0.1 * uIntensity
        ),
        0.0,
        1.0
    );
    
    // Only apply refraction within strip influence zone
    refractedUv = mix(uv, refractedUv, stripInfluence * uIntensity);

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(glass, base, clamp(uOriginalDetailWeight, 0.0, 1.0));
    color += mask * 0.075 * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
