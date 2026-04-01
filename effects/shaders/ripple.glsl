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
    float aspect = uWidth / uHeight;
    vec2 center = vec2(0.50, 0.57);
    vec2 delta = uv - center;
    delta.x *= aspect;

    float dist = length(delta);
    float lens = smoothstep(0.64, 0.0, dist);
    float rings = sin(dist * 42.0 - 0.6) * 0.013 * smoothstep(0.80, 0.06, dist);
    float swirl = (1.0 - smoothstep(0.0, 0.65, dist)) * 0.40 * uIntensity;

    float angle = atan(delta.y, delta.x) + swirl;
    float radius = dist * (1.0 - lens * 0.42 * uIntensity) + rings * uIntensity;

    vec2 displaced = vec2(
        center.x + cos(angle) * radius / aspect,
        center.y + sin(angle) * radius
    );
    displaced = clamp(displaced, 0.0, 1.0);

    vec3 color = texture(uTexture, displaced).rgb;
    color += lens * 0.06 * uIntensity;

    fragColor = vec4(color, 1.0);
}
