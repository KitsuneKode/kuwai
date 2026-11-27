#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 accent;
    vec2 size;
    float t;
};

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = size.x / max(size.y, 1.0);
    vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
    vec2 q = p + 0.22 * vec2(sin(1.9 * p.y + t * 0.07), cos(1.6 * p.x + t * 0.05));
    float a = sin(2.3 * q.x + t * 0.06);
    float b = sin(2.9 * q.y - t * 0.045);
    float c = sin(1.7 * (q.x + q.y) + t * 0.035);
    float v = (a + b + c) / 6.0 + 0.5;

    vec3 ink = vec3(0.016, 0.018, 0.026);
    vec3 deep = mix(ink, accent.rgb, 0.16);
    vec3 glow = mix(accent.rgb, vec3(1.0), 0.18);
    vec3 col = mix(ink, deep, smoothstep(0.25, 0.85, v));
    col += glow * 0.2 * pow(smoothstep(0.55, 1.0, v), 2.0);
    col *= 1.0 - 0.55 * smoothstep(0.25, 0.9, length(p * vec2(0.8, 1.0)));
    float n = fract(sin(dot(uv * size, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
