#version 440
// Liquid glass rim for the expanded island: the black body stays black;
// what reads as glass is the light at its edge. A hairline that brightens
// where the edge faces the light (the pointer, or above), a soft inner
// bevel that fades in a few pixels, and a faint sheen across the top third.
// No backdrop sampling (a layer surface can't see what's under it; the
// compositor's blur does that part).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // px
    vec2 light;     // px, in the item
    float radius;   // bottom corners, px
    float strength; // 0..1
    float full;     // 1: a floating card (all four corners); 0: hangs from the top edge
    float ear;      // px: the notch's concave ears (NotchShape), each side; 0 for none
    vec4 tint;      // the "needs you" light's colour
    float glow;     // 0..1+: something waits on you — the rim lit in tint, inside and out
    float spread;   // px the item reaches past the shape (left, right, below) for the halo
};

// The shape's own box: the item less the halo's room.
vec2 box() { return size - vec2(2.0 * spread, spread); }

// A rounded box (centre p, half size b).
float sdBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The whole outline: the body (bottom corners rounded, top running off the
// item) and, for a notch, the concave ears where it meets the screen edge:
// a strip as wide as body + ears along the top, less a quarter circle at each
// end (NotchShape's PathArcs). So the hairline climbs the side and curves out
// into the edge with the black, instead of running straight up past it.
float shape(vec2 px) {
    vec2 size = box();
    float lift = radius * (1.0 - full);                 // the top edge runs off the item
    vec2 c = vec2(size.x * 0.5, size.y * 0.5 - lift);
    vec2 b = vec2(size.x * 0.5 - ear, size.y * 0.5 + lift);
    float d = sdBox(px - c, b, radius);
    if (ear > 0.5) {
        float strip = sdBox(px - vec2(size.x * 0.5, 0.0), vec2(size.x * 0.5, ear), 0.0);
        float cut = min(length(px - vec2(0.0, ear)), length(px - vec2(size.x, ear))) - ear;
        d = max(min(d, strip), -cut);
    }
    return d;
}

void main() {
    vec2 px = qt_TexCoord0 * size - vec2(spread, 0.0);
    vec2 bs = box();
    float d = shape(px);                                // < 0 inside

    // Something waits on you: the edge lit in tint, bleeding a little inward
    // (light in the glass) and a soft halo outward, strongest below, gone
    // toward the screen edge (the notch hangs from it; nothing glows there).
    vec3 lit = vec3(0.0); float la = 0.0;
    if (glow > 0.001) {
        float edge = smoothstep(1.8, 0.0, abs(d + 0.9));
        float inner = exp(d / 9.0) * step(d, 0.0);
        float halo = exp(-max(d, 0.0) / max(spread * 0.42, 1.0)) * step(0.0, d);
        float down = smoothstep(0.0, bs.y * 0.7, px.y);
        float g = (edge * 0.62 + inner * 0.26 + halo * 0.42 * down) * glow;
        g *= mix(1.0, smoothstep(0.0, 2.5, px.y), step(0.5, ear));
        la = clamp(g * tint.a, 0.0, 1.0);
        lit = tint.rgb * la;
    }
    if (d > 0.5) { fragColor = vec4(lit, la) * qt_Opacity; return; }

    // Edge normal from the SDF's gradient.
    vec2 e = vec2(0.75, 0.0);
    vec2 n = normalize(vec2(shape(px + e.xy) - shape(px - e.xy),
                            shape(px + e.yx) - shape(px - e.yx)) + 1e-5);
    vec2 toL = normalize(light - px + 1e-5);
    float facing = clamp(dot(n, toL) * 0.5 + 0.5, 0.0, 1.0);
    float near = exp(-length(light - px) / max(bs.x, 1.0) * 2.2);

    float hair = smoothstep(1.6, 0.0, abs(d + 0.8));            // ~1.5 px line
    float bevel = exp(d / 7.0) * step(d, 0.0);                  // inner, fades in ~7 px
    float sheen = smoothstep(bs.y * 0.35, 0.0, px.y) * 0.035;

    // An even hairline all round (it follows the corners, not just the flat
    // bottom), brighter where it faces the light.
    float a = hair * (0.26 + 0.38 * facing * (0.45 + 0.55 * near))
            + bevel * 0.06 * facing
            + sheen;
    a *= strength * smoothstep(0.5, -0.5, d);
    a *= mix(1.0, smoothstep(0.0, 2.5, px.y), step(0.5, ear));   // the ears' line dissolves into the edge
    float oa = clamp(a + la * (1.0 - a), 0.0, 1.0);
    fragColor = vec4(vec3(1.0) * a + lit * (1.0 - a), oa) * qt_Opacity;   // premultiplied
}
