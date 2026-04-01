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
    float columns = 10.0;
    float gx = uv.x * columns;
    float localX = fract(gx) - 0.5;
    float ridge = pow(1.0 - smoothstep(0.06, 0.5, abs(localX)), 1.8);
    float rise = pow(uv.y, 1.7);
    float phase = sin(uv.y * 20.0 + floor(gx) * 0.9);

    vec2 finalUv = uv;
    finalUv.x += phase * ridge * 0.006 * uIntensity;
    finalUv.y -= ridge * rise * 0.095 * uIntensity;
    finalUv.y += localX * localX * 0.018 * rise * uIntensity;
    finalUv = clamp(finalUv, 0.0, 1.0);

    vec3 color = texture(uTexture, finalUv).rgb;
    float seam = 1.0 - smoothstep(0.40, 0.50, abs(localX));
    color += ridge * 0.040 * uIntensity;
    color *= 1.0 - seam * 0.08 * uIntensity;

    fragColor = vec4(color, 1.0);
}
