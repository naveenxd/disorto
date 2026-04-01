#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uIntensity;
uniform sampler2D uTexture;
out vec4 fragColor;

float tri(float x) {
    return abs(fract(x) - 0.5) * 2.0;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    vec2 px = 1.0 / vec2(uWidth, uHeight);
    float columns = 34.0;
    float gx = uv.x * columns;
    float col = floor(gx);
    float localX = fract(gx) - 0.5;
    float ridge = pow(1.0 - smoothstep(0.02, 0.5, abs(localX)), 1.5);

    float teethA = sin(uv.y * 96.0 + col * 0.85);
    float teethB = sin(uv.y * 164.0 - col * 1.73);
    float teethC = tri(uv.y * 38.0 + col * 0.11) * 2.0 - 1.0;
    float shard = (teethA * 0.55 + teethB * 0.30 + teethC * 0.15);
    shard = sign(shard) * pow(abs(shard), 1.9);

    float xBend = localX * ridge * 0.060 * uIntensity;
    float xShard = shard * ridge * 0.010 * uIntensity;
    float ySmear = shard * ridge * (0.010 + 0.020 * uv.y) * uIntensity;

    vec2 finalUv = clamp(uv + vec2(xBend + xShard, ySmear), 0.0, 1.0);
    vec3 color = texture(uTexture, finalUv).rgb;

    float seam = 1.0 - smoothstep(0.42, 0.50, abs(localX));
    float highlight = ridge * 0.075 + seam * 0.020;
    float shadow = seam * 0.12;
    color += highlight * uIntensity;
    color *= 1.0 - shadow * uIntensity;

    vec3 left = texture(uTexture, clamp(finalUv - vec2(px.x * 2.0, 0.0), 0.0, 1.0)).rgb;
    vec3 right = texture(uTexture, clamp(finalUv + vec2(px.x * 2.0, 0.0), 0.0, 1.0)).rgb;
    color += (right - left) * ridge * 0.18 * uIntensity;

    fragColor = vec4(color, 1.0);
}
