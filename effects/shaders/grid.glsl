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

float getHeight(vec2 gv) {
    vec2 d = abs(gv) - vec2(0.38);
    float dist = length(max(d, 0.0));
    return 1.0 - smoothstep(0.0, 0.1, dist);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    float aspect = uWidth / uHeight;

    float cellsX = 8.0;
    float cellsY = cellsX / aspect;
    vec2 grid = vec2(cellsX, cellsY);
    vec2 gv = fract(uv * grid) - 0.5;

    // Height map & normals
    float eps = 0.001;
    float hC = getHeight(gv);
    float hR = getHeight(gv + vec2(eps, 0.0));
    float hT = getHeight(gv + vec2(0.0, eps));
    vec2 normal2D = vec2(hC - hR, hC - hT) / eps;

    // Subtle glass refraction - stronger where there's detail
    vec2 refraction = normal2D * 0.04 * uIntensity;
    vec2 sampleUv = clamp(uv + refraction, 0.0, 1.0);

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, sampleUv).rgb;
    vec3 color = mix(glass, base, clamp(uOriginalDetailWeight, 0.0, 1.0));

    // Detect image variation - only apply where there's significant detail
    vec2 texelSize = vec2(1.0 / uWidth, 1.0 / uHeight);
    vec3 rightPixel = texture(uSourceTexture, uv + vec2(texelSize.x, 0.0)).rgb;
    vec3 topPixel = texture(uSourceTexture, uv + vec2(0.0, texelSize.y)).rgb;
    vec3 leftPixel = texture(uSourceTexture, uv - vec2(texelSize.x, 0.0)).rgb;
    vec3 bottomPixel = texture(uSourceTexture, uv - vec2(0.0, texelSize.y)).rgb;
    
    float variation = length(base - rightPixel) + length(base - topPixel) + 
                      length(base - leftPixel) + length(base - bottomPixel);
    
    // Hard threshold - effect only applies on significant detail
    float activityMask = step(0.15, variation);

    // Luminance
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));

    // Subtle glass surface normals
    vec3 normal3D = normalize(vec3(normal2D.x, normal2D.y, 2.2));
    vec3 lightDir = normalize(vec3(-0.5, -0.5, 1.0));

    float diffuse = max(dot(normal3D, lightDir), 0.0);

    // Crisp, subtle specular for glass edge
    vec3 viewDir = vec3(0.0, 0.0, 1.0);
    vec3 halfDir = normalize(lightDir + viewDir);
    float specular = pow(max(dot(normal3D, halfDir), 0.0), 56.0);

    float slopeMask = 1.0 - hC;

    // Glass effect - more pronounced on detail areas
    vec3 shine = vec3(specular) * (0.4 + luminance * 0.5) * 1.8;

    // Apply shine only where there's detail
    color += shine * slopeMask * uIntensity * activityMask;

    // Fine grid lines with tri-level appearance
    float boxDist = max(abs(gv.x), abs(gv.y));
    
    // Thin outer highlight - visible on detail areas
    float outerEdge = smoothstep(0.498, 0.495, boxDist);
    color += vec3(0.2) * outerEdge * activityMask * uIntensity;
    
    // Fine dark grout line - stronger definition
    float grout = smoothstep(0.501, 0.5, boxDist);
    color *= mix(1.0, 0.65, grout * activityMask);
    
    // Inner shadow edge - visible depth
    float innerEdge = smoothstep(0.490, 0.487, boxDist);
    color *= mix(1.0, 0.88, innerEdge * activityMask);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
