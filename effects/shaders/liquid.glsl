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
    float falloff = 0.35 + 0.65 * pow(uv.y, 1.35);
    float warpX =
        sin(uv.y * 8.5 + uv.x * 5.5) * 0.030 +
        sin(uv.y * 15.0 - uv.x * 3.5) * 0.018 +
        sin(uv.y * 28.0 + uv.x * 1.8) * 0.010;
    float warpY =
        sin(uv.x * 9.0 + uv.y * 4.5) * 0.010 +
        sin(uv.x * 18.0 - uv.y * 2.0) * 0.006;

    vec2 warped = uv;
    warped.x += warpX * falloff * uIntensity;
    warped.y += warpY * falloff * uIntensity;
    warped = clamp(warped, 0.0, 1.0);

    vec3 color = texture(uTexture, warped).rgb;
    float sheen = smoothstep(0.0, 1.0, falloff) * 0.04;
    color += sheen * uIntensity;

    fragColor = vec4(color, 1.0);
}
