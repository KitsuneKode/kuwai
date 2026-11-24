#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    vec4 tint;
    vec4 rimColor;
    float sheen;
    float darkRing;
    float grain;
};

float sdBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 over(vec4 src, vec4 dst) {
    return src + dst * (1.0 - src.a);
}

void main() {
    vec2 s = max(size, vec2(2.0));
    vec2 px = qt_TexCoord0 * s;
    vec2 hs = s * 0.5;
    float r = clamp(radius, 0.0, min(hs.x, hs.y));
    float d = sdBox(px - hs, hs, r);
    float aa = smoothstep(0.5, -0.5, d);
    if (aa <= 0.0001) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 dst = vec4(tint.rgb * tint.a, tint.a);

    float yFrac = clamp(px.y / s.y, 0.0, 1.0);
    float lip = smoothstep(3.0, 1.0, px.y) * sheen;
    float glow = smoothstep(0.40, 0.0, yFrac) * sheen * 0.45;
    float sa = clamp(lip + glow, 0.0, 0.45);
    dst = over(vec4(vec3(sa), sa), dst);

    float da = smoothstep(0.70, 1.0, yFrac) * 0.12;
    dst = over(vec4(vec3(0.0), da), dst);

    vec2 e = vec2(0.75, 0.0);
    vec2 n = normalize(vec2(
        sdBox(px + e.xy - hs, hs, r) - sdBox(px - e.xy - hs, hs, r),
        sdBox(px + e.yx - hs, hs, r) - sdBox(px - e.yx - hs, hs, r)
    ) + 1e-5);
    vec2 lightDir = vec2(-0.62, -0.78);
    float key = pow(max(0.0, dot(n, lightDir)), 1.7);
    float bounce = pow(max(0.0, dot(n, -lightDir)), 2.2) * 0.42;
    float rimBand = smoothstep(1.15, 0.15, abs(d + 1.45)) * smoothstep(-0.3, -1.0, d);
    float ra = clamp(rimColor.a * (0.65 + 1.55 * key + 0.65 * bounce) * rimBand, 0.0, 0.65);
    dst = over(vec4(rimColor.rgb * ra, ra), dst);

    if (grain > 0.001) {
        float g = (fract(sin(dot(floor(px), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * min(0.05, grain);
        dst.rgb = clamp(dst.rgb + vec3(g) * dst.a, 0.0, dst.a);
    }

    float ring = smoothstep(-1.35, -0.55, d);
    vec4 ringCol = vec4(0.0, 0.0, 0.0, darkRing);
    dst = mix(dst, ringCol, ring);

    fragColor = dst * aa * qt_Opacity;
}
