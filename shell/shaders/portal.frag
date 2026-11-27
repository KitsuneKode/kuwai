#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 accent;
    vec2 size;
    vec2 center;
    float mode;
    float t;
    float radius;
};
layout(binding = 1) uniform sampler2D source;

const float PI = 3.14159265;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * size;
    vec4 tex = texture(source, uv);
    vec3 light = mix(vec3(1.0, 0.97, 0.92), accent.rgb, 0.22);
    float inside = 0.0;
    float glow = 0.0;

    if (mode < 0.5) {
        float d = length(px - center) - radius;
        float feather = 1.5 + 10.0 * (1.0 - t);
        inside = 1.0 - smoothstep(-feather, feather, d);
        float w = 9.0 + 14.0 * (1.0 - t);
        glow = exp(-(d * d) / (2.0 * w * w)) * (1.0 - smoothstep(0.55, 1.0, t)) * 0.65;
    } else if (mode < 1.5) {
        float open = t * (size.x * 0.5 + 24.0);
        float d = abs(px.x - center.x) - open;
        float feather = 1.0 + 18.0 * t;
        inside = 1.0 - smoothstep(-feather, feather, d);
        float w = 5.0 + 26.0 * t;
        float reach = 1.0 - 0.55 * abs(uv.y - 0.5) * 2.0;
        glow = exp(-(d * d) / (2.0 * w * w)) * sin(PI * clamp(t * 1.15, 0.0, 1.0)) * reach * 0.55;
    } else if (mode < 2.5) {
        inside = t;
    } else {
        float r = length(px - center) / max(length(size * 0.5), 1.0);
        float th = 1.06 - 1.16 * t;
        inside = smoothstep(th - 0.16, th + 0.04, r);
    }

    vec3 rgb = tex.rgb * inside + light * glow;
    float alpha = clamp(tex.a * inside + glow * 0.55, 0.0, 1.0);
    fragColor = vec4(rgb, alpha) * qt_Opacity;
}
