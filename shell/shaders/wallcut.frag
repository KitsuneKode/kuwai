#version 440
// A wallpaper change that arrives in pieces (kuwai's; the idea of a change
// drawn by the shell, and of a subject drawn first, is after pocket-dots'
// wallfx, but nothing here is taken from it).
//
//   mode 0  SHARDS, any wallpaper. The screen is cut into glass pieces
//           (a jittered Voronoi, about 22 across the diagonal). Each piece
//           turns over to the new picture on its own beat, earlier the
//           closer it is to the notch, so the change spreads from the island
//           in cuts. A piece slides the last few pixels into place and its
//           light settles; the cuts catch a hairline of light while they move.
//   mode 1  SUBJECT, when bin/kuwai-wallmap has cut the subject out (an
//           optional model, cached per wallpaper). A thin line traces the
//           subject's outline, the subject fills in from it, and the rest of
//           the picture spreads outward from the subject's edge.
//
// t runs 0 → 1, eased by the caller. Everything extra (slides, light, the
// line) is scaled by sin(πt) or by a piece's own (1 − p), so t = 0 is exactly
// the old picture and t = 1 exactly the new one: the layer can appear and go
// without a seam.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
// qt_Matrix and qt_Opacity first; then the vec2s (8-byte aligned), then floats.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // px
    vec2 origin;    // px, the notch
    float t;        // 0..1
    float mode;     // 0 shards, 1 subject, 2 contour
    float seed;     // a new one every change: the pieces never repeat
    vec4 cropA;
    vec4 cropB;
};
layout(binding = 1) uniform sampler2D before;
layout(binding = 2) uniform sampler2D after;
// mode 1: R = when each pixel turns (0 the outline … 1 the farthest corner),
//         G = closeness to the outline (1 on it). Unused in mode 0.
layout(binding = 3) uniform sampler2D order;

const float PI = 3.14159265;

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))) + seed;
    return fract(sin(p) * 43758.5453);
}
float hash1(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1)) + seed * 1.7) * 23421.631); }

vec2 ca(vec2 uv) { return cropA.xy + uv * cropA.zw; }
vec2 cb(vec2 uv) { return cropB.xy + uv * cropB.zw; }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * size;
    float env = sin(PI * clamp(t, 0.0, 1.0));      // 0 at both ends

    if (mode < 0.5) {
        // ── shards ──────────────────────────────────────────────────────
        float cell = length(size) / 22.0;
        vec2 g = px / cell;
        vec2 gi = floor(g);
        float d1 = 1e9, d2 = 1e9;
        vec2 site = vec2(0.0), id = vec2(0.0);
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 c = gi + vec2(float(x), float(y));
                vec2 s = c + 0.15 + 0.7 * hash2(c);
                float d = length(g - s);
                if (d < d1) { d2 = d1; d1 = d; site = s; id = c; }
                else if (d < d2) { d2 = d; }
            }
        }
        float edge = (d2 - d1) * cell;               // px to the nearest cut (≈)
        vec2 sitePx = site * cell;
        float far = length(max(origin, size - origin));
        // When this piece turns: by its distance from the notch, plus its own
        // jitter. Starts in [0, 0.86]; each turn takes 0.14 of t, so every
        // piece has finished by t = 1.
        float start = 0.62 * clamp(length(sitePx - origin) / far, 0.0, 1.0) + 0.24 * hash1(id);
        float p = clamp((t - start) / 0.14, 0.0, 1.0);
        p = p * p * (3.0 - 2.0 * p);
        // The piece slides the last few pixels toward its place, away from the notch.
        vec2 dir = normalize(sitePx - origin + 0.001);
        vec2 slide = dir * (1.0 - p) * cell * 0.10;
        vec4 o = texture(before, ca(uv));
        vec4 n = texture(after, cb((px - slide) / size));
        // A piece is either old or new: it flips over a few frames, not a crossfade.
        float flip = smoothstep(0.0, 0.35, p);
        vec4 c = mix(o, n, flip);
        // Its light settles: a touch brighter as it lands (more washed a
        // dark wallpaper out to grey).
        c.rgb *= 1.0 + 0.10 * (1.0 - p) * flip;
        // The cuts: a hairline of light along the edges of pieces near the
        // front (turning now, or about to), not over the whole screen.
        float moving = 4.0 * p * (1.0 - p);
        float near = exp(-abs(t - start - 0.07) * 9.0);
        float cut = (1.0 - smoothstep(0.6, 1.6, edge)) * max(moving, 0.6 * near);
        c.rgb = mix(c.rgb, vec3(1.0), 0.42 * cut * env);
        fragColor = c * qt_Opacity;
    } else if (mode > 1.5) {
        vec2 o1 = 1.0 / size;
        vec3 W = vec3(0.2126, 0.7152, 0.0722);
        float tl = dot(texture(after, cb(uv + o1 * vec2(-1.0, -1.0))).rgb, W);
        float tc = dot(texture(after, cb(uv + o1 * vec2(0.0, -1.0))).rgb, W);
        float tr = dot(texture(after, cb(uv + o1 * vec2(1.0, -1.0))).rgb, W);
        float ml = dot(texture(after, cb(uv + o1 * vec2(-1.0, 0.0))).rgb, W);
        float mr = dot(texture(after, cb(uv + o1 * vec2(1.0, 0.0))).rgb, W);
        float bl = dot(texture(after, cb(uv + o1 * vec2(-1.0, 1.0))).rgb, W);
        float bc = dot(texture(after, cb(uv + o1 * vec2(0.0, 1.0))).rgb, W);
        float br = dot(texture(after, cb(uv + o1 * vec2(1.0, 1.0))).rgb, W);
        float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
        float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
        float e = length(vec2(gx, gy));
        vec4 n = texture(after, cb(uv));
        float lum = dot(n.rgb, W);
        float far = length(max(origin, size - origin));
        float dist = clamp(length(px - origin) / far, 0.0, 1.0);
        float sketch = mix(-0.05, 1.12, clamp(t / 0.55, 0.0, 1.0));
        float drawn = smoothstep(sketch, sketch - 0.10, dist);
        float edge = smoothstep(0.16, 0.40, e) * drawn;
        float wob = (hash1(floor(px / 4.0)) - 0.5) * 0.02;
        float ord = 0.60 * dist + 0.25 * (1.0 - lum) + 0.15 * (1.0 - clamp(e * 3.0, 0.0, 1.0));
        float front = mix(-0.08, 1.08, clamp((t - 0.18) / 0.82, 0.0, 1.0));
        float k = smoothstep(front + 0.03, front - 0.03, ord + wob);
        vec4 c = mix(texture(before, ca(uv)), n, k);
        c.rgb = mix(c.rgb, vec3(1.0), 0.5 * edge * (1.0 - k) * env);
        fragColor = c * qt_Opacity;
    } else {
        // ── subject ─────────────────────────────────────────────────────
        vec4 m = texture(order, cb(uv));
        // An organic front: the order nudged by a little noise per 4 px block.
        float wob = (hash1(floor(px / 4.0)) - 0.5) * 0.025;
        float front = mix(-0.06, 1.06, t);
        float k = smoothstep(front + 0.02, front - 0.02, m.r + wob);
        vec4 c = mix(texture(before, ca(uv)), texture(after, cb(uv)), k);
        // The line along the subject's outline, drawn in the first 40 %.
        float draw = sin(PI * clamp(t / 0.4, 0.0, 1.0));
        float line = smoothstep(0.82, 0.97, m.g) * draw;
        c.rgb = mix(c.rgb, vec3(1.0), 0.75 * line);
        // A thin light just ahead of the front (a wide one read as haze).
        float glow = exp(-abs(m.r + wob - front) * 160.0) * env * 0.10;
        c.rgb += glow;
        fragColor = c * qt_Opacity;
    }
}
