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
    float columns = 18.0;
    float gx = uv.x * columns;
    float col = floor(gx);
    float localX = fract(gx) - 0.5;
    float ridge = pow(1.0 - smoothstep(0.03, 0.5, abs(localX)), 1.3);

    float plumeA = sin(uv.y * 58.0 + col * 0.52);
    float plumeB = sin(uv.y * 103.0 - col * 1.07);
    float plumeC = tri(uv.y * 23.0 + col * 0.19) * 2.0 - 1.0;
    float plume = plumeA * 0.52 + plumeB * 0.28 + plumeC * 0.20;
    plume = sign(plume) * pow(abs(plume), 1.6);

    float xLens = localX * ridge * 0.110 * uIntensity;
    float xShear = plume * ridge * 0.014 * uIntensity;
    float yDrift = (localX * 0.035 + plume * 0.018) * (0.35 + uv.y * 0.65) * uIntensity;

    vec2 finalUv = clamp(uv + vec2(xLens + xShear, yDrift), 0.0, 1.0);
    vec3 color = texture(uTexture, finalUv).rgb;

    float seam = 1.0 - smoothstep(0.40, 0.50, abs(localX));
    float crown = ridge * 0.060;
    color += (crown + seam * 0.020) * uIntensity;
    color *= 1.0 - seam * 0.10 * uIntensity;

    vec3 left = texture(uTexture, clamp(finalUv - vec2(px.x * 3.0, 0.0), 0.0, 1.0)).rgb;
    vec3 right = texture(uTexture, clamp(finalUv + vec2(px.x * 3.0, 0.0), 0.0, 1.0)).rgb;
    color += (right - left) * ridge * 0.14 * uIntensity;

    fragColor = vec4(color, 1.0);
}
