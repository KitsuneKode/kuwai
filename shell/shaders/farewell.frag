#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 accent;
    vec4 coolTint;
    vec2 size;
    vec2 center;
    float mode;
    float tIn;
    float tMark;
    float tOut;
};

const float PI = 3.14159265;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * size;
    float sMin = max(min(size.x, size.y), 1.0);
    vec2 dp = px - center;
    vec2 p = dp / sMin;
    float rPx = length(dp);
    float rNorm = length(p);
    vec3 rgb = vec3(0.0);
    float alpha = 0.0;

    if (mode < 0.5) {
        float vig = smoothstep(0.15, 0.95, rNorm);
        float roomA = clamp(tIn * (0.78 + 0.20 * vig), 0.0, 0.96);
        alpha = mix(roomA, 1.0, max(tMark, smoothstep(0.0, 0.25, tOut)));
        float cool = clamp(tMark * 0.72 + tOut * 0.50, 0.0, 1.0);
        vec3 lampCol = cool < 0.55 ? mix(vec3(1.0, 0.96, 0.90), vec3(1.0, 0.56, 0.22), cool / 0.55)
                                   : mix(vec3(1.0, 0.56, 0.22), vec3(0.45, 0.10, 0.02), (cool - 0.55) / 0.45);
        float poolR = mix(0.40, 0.14, tMark);
        float pool = exp(-dot(p, p) / max(poolR * poolR, 0.0004)) * tIn * (1.0 - tOut) * 0.20;
        float ry = mix(0.11, 0.0022, smoothstep(0.0, 0.55, tOut));
        float rx = mix(0.26, 0.0040, smoothstep(0.18, 0.85, tOut));
        float fd = length(vec2(p.x / max(rx, 0.001), p.y / max(ry, 0.001)));
        float core = exp(-fd * fd * 1.8);
        float halo = 0.30 * exp(-rNorm / mix(0.13, 0.02, tOut));
        float tail = max(1.0 - smoothstep(0.22, 0.98, tOut), 0.0);
        float ext = smoothstep(0.0, 0.18, tOut) * tail * tail;
        rgb = lampCol * (pool + (core * 0.85 + halo * 0.35) * ext);
    } else if (mode < 1.5) {
        alpha = clamp(max(tIn * 0.86, max(tMark * 0.94, smoothstep(0.0, 0.30, tOut))), 0.0, 1.0);
        float ringR = mix(46.0, 0.0, smoothstep(0.0, 0.85, tOut));
        float dR = rPx - ringR;
        float ang = atan(dp.y, dp.x);
        float cs = 0.5 + 0.5 * cos(ang - tMark * 3.0 * PI);
        float sweep = 0.42 + 0.58 * cs * cs * cs;
        float line = exp(-(dR * dR) / 3.2);
        float glow = 0.22 * exp(-(dR * dR) / 144.0);
        float env = tIn * max(1.0 - smoothstep(0.55, 0.98, tOut), 0.0);
        rgb = mix(vec3(1.0), accent.rgb, 0.25) * (line * 0.55 * sweep + glow) * env;
    } else if (mode < 2.5) {
        float ny = abs(uv.y - 0.5) * 2.0;
        float close = clamp(tIn * 0.55 + tMark * 0.20 + tOut * 0.25, 0.0, 1.0);
        float edge = 1.0 - close * 1.25;
        float curtain = smoothstep(edge - 0.35, edge + 0.15, ny);
        alpha = clamp(max(curtain * clamp(tIn * 1.15, 0.0, 1.0), smoothstep(0.0, 0.70, tOut)), 0.0, 1.0);
        vec3 base = mix(coolTint.rgb * 0.08, vec3(0.0), smoothstep(0.20, 1.0, tOut));
        float breathe = 0.7 + 0.3 * sin(PI * tMark);
        float lunar = exp(-dot(p, p) / 0.055) * tIn * (1.0 - tOut) * 0.16 * breathe;
        rgb = base * alpha + mix(vec3(0.88, 0.92, 1.0), coolTint.rgb, 0.25) * lunar;
    } else {
        float halfW = max(size.x * 0.5, 1.0);
        float ax = abs(px.x - halfW);
        float edgeX = mix(halfW + 48.0, halfW * 0.14, clamp(tIn, 0.0, 1.0)) * (1.0 - clamp(tMark, 0.0, 1.0));
        float d = ax - edgeX;
        float door = smoothstep(-0.75, 0.75, d);
        float paneFrac = clamp(d / halfW, 0.0, 1.0);
        float bevel = exp(-max(d, 0.0) / 16.0) * (1.0 - tOut);
        vec3 glass = vec3(0.035, 0.035, 0.05);
        vec3 baseCol = mix(glass * (1.15 - 0.30 * paneFrac) + vec3(0.04 * bevel), vec3(0.0), clamp(tOut, 0.0, 1.0));
        float doorA = mix(0.92, 1.0, max(tMark * 0.65, tOut)) * door;
        float lit = px.x < halfW ? 1.0 : 0.72;
        float rim = exp(-(d / 1.4) * (d / 1.4)) * lit * (1.0 - tOut) * (1.0 - 0.85 * tMark) * smoothstep(0.0, 0.08, tIn);
        float shD = max(-d, 0.0) / 28.0;
        float shA = 0.22 * exp(-shD * shD) * step(d, 0.0) * smoothstep(0.0, 0.12, tIn) * (1.0 - tMark);
        float lt = clamp((tMark - 0.65) / 0.35, 0.0, 1.0);
        float latch = sin(PI * lt) * (1.0 - tOut);
        float vy = abs(uv.y - 0.5) * 2.0;
        float reach = smoothstep(0.25 + 0.75 * lt, 0.0, vy);
        float seam = exp(-(ax / 1.5) * (ax / 1.5)) + 0.22 * exp(-(ax / 12.0) * (ax / 12.0));
        rgb = baseCol * doorA + vec3(0.32 * rim) + mix(vec3(1.0), accent.rgb, 0.18) * (seam * reach * latch * 0.65);
        alpha = clamp(doorA + shA * (1.0 - doorA) + rim * 0.2, 0.0, 1.0);
    }

    float last = smoothstep(0.80, 1.0, tOut);
    rgb = mix(rgb, vec3(0.0), last);
    alpha = max(alpha, last);
    fragColor = vec4(rgb, alpha) * qt_Opacity;
}
