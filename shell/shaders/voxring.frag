#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float pad;
    float radius;
    float stroke;
    float mode;
    float phase;
    vec4 hist0;
    vec4 hist1;
    vec4 listenColor;
    vec4 writeColor;
    vec4 writeColor2;
};

float sdBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hist(int i) {
    vec4 h = i < 4 ? hist0 : hist1;
    int k = i < 4 ? i : i - 4;
    return k == 0 ? h.x : k == 1 ? h.y : k == 2 ? h.z : h.w;
}

float level(float s) {
    float f = clamp(s, 0.0, 1.0) * 7.0;
    int i = int(floor(f));
    float t = f - float(i);
    float a = hist(min(i, 7));
    float b = hist(min(i + 1, 7));
    return mix(a, b, smoothstep(0.0, 1.0, t));
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 hs = size * 0.5;
    vec2 p = px - hs;
    vec2 box = max(hs - vec2(pad), vec2(1.0));
    float d = sdBox(p, box, min(radius, min(box.x, box.y)));
    if (d < -stroke - 1.0 || d > pad) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 q = p / box;
    float around = atan(q.x, -q.y) / 3.14159265;

    float s = abs(around);
    float amp = level(s) * (1.0 - 0.35 * s);
    float ripple = 0.5 + 0.5 * sin(s * 46.0 - hist0.x * 3.0);
    float wave = amp * (0.75 + 0.25 * ripple);
    float half_ = stroke * 0.5 + wave * stroke * 1.6;
    float line = smoothstep(half_ + 0.75, half_ - 0.75, abs(d + stroke * 0.5));
    float halo = (d > 0.0 ? exp(-d / (2.5 + 9.0 * wave)) : 0.0) * wave * 0.85;
    vec3 hot = mix(listenColor.rgb, vec3(1.0, 0.72, 0.62), clamp(wave * 0.6, 0.0, 0.5));
    float la = clamp(line * (0.55 + 0.45 * wave) + halo, 0.0, 1.0) * listenColor.a;
    vec4 listen = vec4(hot * la, la);

    float u = fract(around * 0.5 + 0.5);
    float h1 = fract(phase - u);
    float h2 = fract(phase + 0.5 - u);
    float c1 = smoothstep(0.30, 0.04, h1) * smoothstep(0.0, 0.04, h1);
    float c2 = smoothstep(0.30, 0.04, h2) * smoothstep(0.0, 0.04, h2);
    float comet = max(c1, c2);
    float tail = c1 > c2 ? h1 : h2;
    vec3 wc = mix(writeColor.rgb, writeColor2.rgb, clamp(tail * 3.5, 0.0, 1.0));
    float w_half = stroke * 0.5 + comet * stroke * 0.6;
    float wline = smoothstep(w_half + 0.75, w_half - 0.75, abs(d + stroke * 0.5));
    float wglow = (d > 0.0 ? exp(-d / (2.0 + 4.0 * comet)) : 0.0) * comet * comet * 0.6;
    vec3 rgb = mix(writeColor.rgb, wc, comet);
    float wa = clamp(wline * (0.22 + 0.78 * comet) + wglow, 0.0, 1.0) * writeColor.a;
    vec4 write = vec4(rgb * wa, wa);

    fragColor = mix(listen, write, clamp(mode, 0.0, 1.0)) * qt_Opacity;
}
