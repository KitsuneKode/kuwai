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
};

// A box whose top edge runs off the item: only the bottom corners round.
float sdBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 c = vec2(size.x * 0.5, (size.y - radius * 2.0) * 0.5);
    vec2 b = vec2(size.x * 0.5, size.y * 0.5 + radius);
    float d = sdBox(px - c, b, radius);                 // < 0 inside
    if (d > 0.5) { fragColor = vec4(0.0); return; }

    // Edge normal from the SDF's gradient.
    vec2 e = vec2(0.75, 0.0);
    vec2 n = normalize(vec2(sdBox(px - c + e.xy, b, radius) - sdBox(px - c - e.xy, b, radius),
                            sdBox(px - c + e.yx, b, radius) - sdBox(px - c - e.yx, b, radius)) + 1e-5);
    vec2 toL = normalize(light - px + 1e-5);
    float facing = clamp(dot(n, toL) * 0.5 + 0.5, 0.0, 1.0);
    float near = exp(-length(light - px) / max(size.x, 1.0) * 2.2);

    float hair = smoothstep(1.6, 0.0, abs(d + 0.8));            // ~1.5 px line
    float bevel = exp(d / 7.0) * step(d, 0.0);                  // inner, fades in ~7 px
    float sheen = smoothstep(size.y * 0.35, 0.0, px.y) * 0.035;

    float a = hair * (0.16 + 0.60 * facing * (0.35 + 0.65 * near))
            + bevel * 0.06 * facing
            + sheen;
    a *= strength * smoothstep(0.5, -0.5, d);
    fragColor = vec4(vec3(1.0) * a, a) * qt_Opacity;           // premultiplied
}
