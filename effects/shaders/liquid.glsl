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
    float curve = sin(uv.y * 3.14159 * 2.0 + uTime * 0.4) * 0.08;
    float bar   = fract((uv.x + curve) * count);
    float normal = (bar - 0.5) * 2.0;
    float reed  = normal * pow(abs(normal), 1.2);

    float dReed = pow(abs(normal), 0.2) * sign(normal) * 1.3;

    float refractX = reed  * 0.185 * uIntensity;
    float refractY = dReed * 0.025 * uIntensity; // pulled way back

    // Fresnel only at the very sharp edge, very dim
    float fresnel = pow(abs(normal), 6.0) * 0.06;

    vec2 warpedUV = clamp(uv + vec2(refractX, refractY), 0.0, 1.0);

    vec3 blurred  = texture(uBlurTexture,  warpedUV).rgb;
    vec3 original = texture(uSourceTexture, warpedUV).rgb;
    vec3 color    = mix(blurred, original, clamp(uOriginalDetailWeight, 0.0, 1.0));

    color += fresnel;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}