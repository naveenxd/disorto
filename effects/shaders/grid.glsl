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

// 1. HEIGHTMAP
float getHeight(vec2 gv) {
    vec2 d = abs(gv) - vec2(0.38); // Flat center size
    float dist = length(max(d, 0.0));
    return 1.0 - smoothstep(0.0, 0.1, dist);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
    float aspect = uWidth / uHeight;
    
    // Grid Setup
    float cellsX = 8.0; 
    float cellsY = cellsX / aspect;
    vec2 grid = vec2(cellsX, cellsY);
    vec2 gv = fract(uv * grid) - 0.5;

    // 2. NORMALS (3D slope mapping)
    float eps = 0.001;
    float hC = getHeight(gv);
    float hR = getHeight(gv + vec2(eps, 0.0));
    float hT = getHeight(gv + vec2(0.0, eps));
    vec2 normal2D = vec2(hC - hR, hC - hT) / eps;

    // 3. REFRACTION
    vec2 refraction = normal2D * 0.005 * uIntensity;
    vec2 sampleUv = clamp(uv + refraction, 0.0, 1.0);

    vec3 base = texture(uSourceTexture, uv).rgb;
    vec3 glass = texture(uBlurTexture, sampleUv).rgb;
    vec3 color = mix(glass, base, clamp(uOriginalDetailWeight, 0.0, 1.0));

    // -------------------------------------------------------------
    // THE FIX: Nuvvu cheppina "Black place lo lines" problem ki solution
    // -------------------------------------------------------------
    // Image loni brightness (luminance) ni calculate chesthunnam.
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));

    // 4. LIGHTING
    vec3 normal3D = normalize(vec3(normal2D.x, normal2D.y, 1.5));
    vec3 lightDir = normalize(vec3(-1.0, -1.0, 1.2));
    
    // Diffuse (Velugu/Cheekati shadows)
    float diffuse = max(dot(normal3D, lightDir), 0.0);
    
    // Specular (Glass Edge Shine)
    vec3 viewDir = vec3(0.0, 0.0, 1.0);
    vec3 halfDir = normalize(lightDir + viewDir);
    float specular = pow(max(dot(normal3D, halfDir), 0.0), 20.0);

    float slopeMask = 1.0 - hC;

    // Nenu raw white light add cheyakunda, LUMINANCE tho multiply chesthunna.
    // Background pure black (0.0) unte, shine kuda (0.0) aipothundi. No lines!
    vec3 shine = vec3(specular) * luminance * 1.5;

    color *= mix(1.0, diffuse * 1.5, slopeMask * uIntensity);
    color += shine * slopeMask * uIntensity;

    // 5. BLACK GRID LINES (Grout)
    float boxDist = max(abs(gv.x), abs(gv.y));
    float grout = smoothstep(0.48, 0.5, boxDist);
    color *= (1.0 - grout);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}