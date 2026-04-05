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
    float curve = -sin(uv.y * 3.14159 * 2.8 - uTime * 0.4) * 0.08;
    float bar    = fract((uv.x + curve) * count);

    // Anti-alias the band edge — smooth 1px transition at seam
    float edgeWidth = count / uWidth;
    float aa = smoothstep(0.0, edgeWidth, bar) * smoothstep(1.0, 1.0 - edgeWidth, bar);

    float normal = (bar - 0.5) * 2.0;
    float reed   = normal * pow(abs(normal), 1.2) * aa;

    float refractX = reed * 0.185 * uIntensity;

    vec2 warpedUV = clamp(vec2(uv.x + refractX, uv.y), 0.0, 1.0);

    vec3 blurred  = texture(uBlurTexture,  warpedUV).rgb;
    vec3 original = texture(uSourceTexture, warpedUV).rgb;
    vec3 color    = mix(blurred, original, clamp(uOriginalDetailWeight, 0.0, 1.0));

    float lensCurve = cos(normal * 3.14159 * 0.5);
    float shadow    = lensCurve * 0.10;
    float fresnel   = pow(abs(normal), 5.0) * 0.02;

    color -= shadow;
    color += fresnel;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}