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

    float count = 10.0;
    float bar    = fract(uv.x * count);
    float normal = (bar - 0.5) * 2.0;
    float reed   = normal * pow(abs(normal), 1.2);

    float refractX = reed * 0.185 * uIntensity;

    vec2 warpedUV = clamp(vec2(uv.x + refractX, uv.y), 0.0, 1.0);

    vec3 blurred  = texture(uBlurTexture,  warpedUV).rgb;
    vec3 original = texture(uSourceTexture, warpedUV).rgb;
    vec3 color    = mix(blurred, original, clamp(uOriginalDetailWeight, 0.0, 1.0));

    // Two bright lines at edges with a dark gap between them
    float leftEdge  = pow(1.0 - bar, 12.0) * 0.18;
    float rightEdge = pow(bar, 12.0) * 0.18;
    float leftEdge2  = pow(1.0 - max(bar - 0.06, 0.0), 18.0) * 0.10;
    float rightEdge2 = pow(max(bar - (1.0 - 0.06), 0.0) / 0.06, 2.0) * 0.10;

    // Dark separation between the two left lines and two right lines
    float leftGap  = smoothstep(0.0, 0.06, bar) * (1.0 - smoothstep(0.06, 0.14, bar)) * 0.08;
    float rightGap = smoothstep(1.0, 0.94, bar) * (1.0 - smoothstep(0.94, 0.86, bar)) * 0.08;

    color += leftEdge + rightEdge + leftEdge2 + rightEdge2;
    color -= leftGap + rightGap;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}