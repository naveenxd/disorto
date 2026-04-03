#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform float uTime;
uniform sampler2D uSourceTexture;
uniform sampler2D uBlurTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    float noise = sin(uv.y * 80.0 + uv.x * 40.0 + uTime) * 0.002;
    uv.x += noise;

    float aspect = uWidth / uHeight;
    vec2 center = vec2(0.50, 0.56);
    vec2 delta = uv - center;
    delta.x *= aspect;

    float dist = length(delta);
    float lens = 1.0 - smoothstep(0.0, 0.34, dist);
    float ring = sin(dist * 34.0 - uTime * 4.5) * smoothstep(0.42, 0.05, dist);
    float outerRing = sin(dist * 20.0 - uTime * 2.2) * smoothstep(0.95, 0.22, dist);

    float warpedRadius = dist * (1.0 - lens * 0.58 * uIntensity) +
        ring * 0.028 * uIntensity +
        outerRing * 0.010 * uIntensity;
    float angle = atan(delta.y, delta.x);
    vec2 refractedUv = vec2(
        center.x + cos(angle) * warpedRadius / aspect,
        center.y + sin(angle) * warpedRadius
    );
    refractedUv = clamp(refractedUv, 0.0, 1.0);

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(base, glass, clamp(lens * 0.78 * uIntensity, 0.0, 0.70));
    color += lens * 0.10 * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
