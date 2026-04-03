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
    float noise = fract(sin(dot((uv + vec2(uTime * 0.01, uTime * 0.012)) * 100.0, vec2(12.9898, 78.233))) * 43758.5453);
    uv += (noise - 0.5) * 0.002;

    float aspect = uWidth / uHeight;
    vec2 center = vec2(0.50, 0.56);
    vec2 delta = uv - center;
    delta.x *= aspect;

    float dist = length(delta);
    float lens = 1.0 - smoothstep(0.0, 0.34, dist);
    float ring = sin(dist * 36.0 - uTime * 4.8) * smoothstep(0.44, 0.05, dist);
    float outerRing = sin(dist * 22.0 - uTime * 2.4) * smoothstep(0.95, 0.20, dist);

    float warpedRadius = dist * (1.0 - lens * 0.88 * uIntensity) +
        ring * 0.040 * uIntensity +
        outerRing * 0.016 * uIntensity;
    float angle = atan(delta.y, delta.x);
    vec2 refractedUv = vec2(
        center.x + cos(angle) * warpedRadius / aspect,
        center.y + sin(angle) * warpedRadius
    );
    refractedUv = clamp(refractedUv, 0.0, 1.0);

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(base, glass, clamp((0.30 + lens * 0.42) * uIntensity, 0.0, 0.72));
    float edge = smoothstep(0.25, 0.0, dist);
    color += lens * 0.12 * uIntensity + edge * 0.06 * uIntensity;
    color *= 1.0 - edge * 0.06 * uIntensity;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
