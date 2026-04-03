#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform sampler2D uSourceTexture;
uniform sampler2D uBlurTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);

    float count = 10.0;
    float bar = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float mask = pow(max(1.0 - abs(normal), 0.0), 4.0);
    float rise = pow(uv.y, 1.6);

    vec2 refractedUv = clamp(
        vec2(uv.x, uv.y - mask * rise * 0.010 * uIntensity),
        0.0,
        1.0
    );

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, refractedUv).rgb;
    vec3 color = mix(base, glass, (0.04 + 0.06 * mask * rise) * uIntensity);
    color += mask * 0.020 * uIntensity;

    fragColor = vec4(color, 1.0);
}
