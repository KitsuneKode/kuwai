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
    float inward;
    float still;
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
    if (d > pad || d < -stroke - pad) {
        fragColor = vec4(0.0);
        return;
    }
    float side = inward > 0.5 ? -stroke - d : d;
    vec2 q = p / box;
    float around = atan(q.x, -q.y) / 3.14159265;
    float centre = abs(d + stroke * 0.5);

    float s = abs(around);
    float travel = 1.0 - still;
    float lv = mix(hist0.x, level(s) * (1.0 - 0.3 * s), travel);
    float ripple = 0.5 + 0.5 * sin(s * 46.0 - hist0.x * 3.0);
    float wave = lv * mix(1.0, 0.8 + 0.2 * ripple, travel);
    float half_ = stroke * 0.5 + wave * stroke * 0.9 * travel;
    float line = smoothstep(half_ + 0.75, half_ - 0.75, centre);
    float halo = side > 0.0 ? exp(-side / (3.0 + 10.0 * wave)) * (0.14 + 0.7 * wave) : 0.0;
    vec3 hot = mix(listenColor.rgb, vec3(1.0, 0.72, 0.62), clamp(wave * 0.6, 0.0, 0.5));
    float la = clamp(line * (0.72 + 0.28 * wave) + halo, 0.0, 1.0) * listenColor.a;
    vec4 listen = vec4(hot * la, la);

    float u = fract(around * 0.5 + 0.5);
    float h = fract(phase - u);
    float comet = travel * smoothstep(0.4, 0.0, h) * smoothstep(0.0, 0.03, h);
    vec3 wc = mix(writeColor.rgb, writeColor2.rgb, clamp(h * 2.5, 0.0, 1.0));
    float w_half = stroke * 0.5 + comet * stroke * 0.4;
    float wline = smoothstep(w_half + 0.75, w_half - 0.75, centre);
    float wglow = side > 0.0 ? exp(-side / (3.0 + 5.0 * comet)) * (0.12 + 0.5 * comet * comet) : 0.0;
    vec3 rgb = mix(writeColor.rgb, wc, comet);
    float wa = clamp(wline * (0.5 + 0.5 * comet + 0.25 * still) + wglow, 0.0, 1.0) * writeColor.a;
    vec4 write = vec4(rgb * wa, wa);

    fragColor = mix(listen, write, clamp(mode, 0.0, 1.0)) * qt_Opacity;
}
