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

    // Sample brightness at the CURRENT pixel (no noise, no horizontal sin)
    vec3 srcColor = texture(uTexture, uv).rgb;
    float brightness = dot(srcColor, vec3(0.299, 0.587, 0.114));

    // Displace Y UPWARD proportional to brightness.
    // Stronger at the bottom (1.0 - uv.y is large there), fades toward top.
    // Bright pixels "spike" upward — the mountain peaks elongate dramatically.
    float dispY = brightness * uIntensity * 0.4 * (1.0 - uv.y);
    vec2 finalUv = clamp(vec2(uv.x, uv.y - dispY), 0.0, 1.0);

    fragColor = vec4(texture(uTexture, finalUv).rgb, 1.0);
}