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

    // Correct for aspect ratio so ripples are circular, not elliptical
    float aspect = uWidth / uHeight;
    vec2 center  = vec2(0.5, 0.5);
    vec2 delta   = uv - center;
    delta.x     *= aspect;

    float dist  = length(delta);
    float angle = atan(delta.y, delta.x);

    // Radial ripple: sin-based rings with exponential decay
    float ripple = sin(dist * 25.0) * exp(-dist * 3.0) * 0.04 * uIntensity;

    // Swirl: rotate pixels based on distance from centre.
    // Strongest at centre (dist≈0), fades outward.
    float swirl = uIntensity * (1.0 - dist) * 1.5;
    float newAngle = angle + swirl;

    // Reconstruct displaced position
    vec2 displaced;
    displaced.x = center.x + cos(newAngle) * (dist + ripple) / aspect;
    displaced.y = center.y + sin(newAngle) * (dist + ripple);
    displaced    = clamp(displaced, 0.0, 1.0);

    // Subtle chromatic aberration (~0.002 UV offset)
    float caStrength = 0.002 * uIntensity;
    vec2 caOffset    = normalize(delta + vec2(0.0001)) * caStrength;
    float r = texture(uTexture, clamp(displaced + caOffset, 0.0, 1.0)).r;
    float g = texture(uTexture, displaced).g;
    float b = texture(uTexture, clamp(displaced - caOffset, 0.0, 1.0)).b;

    fragColor = vec4(r, g, b, 1.0);
}