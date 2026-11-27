#version 440
// A wallpaper change, out of the island: the new picture grows as a circle
// from the notch (top centre) over the old one. Its edge is a lens of liquid
// glass, not a wipe: just inside the front the new picture is pulled outward
// (refraction), a thin rim catches light, and the band is only ~6 % of the
// screen wide. Everything extra is scaled by sin(πt), so t = 0 is exactly the
// old picture and t = 1 exactly the new one: the layer can appear and go
// without a seam. (Idea after pocket-dots' wallfx: a change is an event on its
// own short-lived layer; this shader and its look are kuwai's.)
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // px
    vec2 origin;    // px, where it grows from (the notch)
    float t;        // 0..1, eased by the caller
    vec4 cropA;
    vec4 cropB;
};
layout(binding = 1) uniform sampler2D before;
layout(binding = 2) uniform sampler2D after;

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 d = px - origin;
    float dist = length(d);
    // Far enough to cover the farthest corner, plus the band.
    float far = length(max(origin, size - origin)) * 1.08;
    float band = 0.06 * length(size);
    float s = t * t * (3.0 - 2.0 * t);
    float r = mix(-band, far, sqrt(s));
    // 0 outside (old), 1 well inside (new); the band between.
    float inside = clamp((r - dist) / band, 0.0, 1.0);
    float lens = sin(3.14159265 * inside) * sin(3.14159265 * t);   // the front, only mid-change
    vec2 dir = dist > 0.5 ? d / dist : vec2(0.0, 1.0);
    // Refraction: the new picture, near the front, sampled from further in.
    vec2 uvNew = qt_TexCoord0 - dir * (lens * 0.018);
    vec4 a = texture(before, cropA.xy + qt_TexCoord0 * cropA.zw);
    vec4 b = texture(after, cropB.xy + clamp(uvNew, vec2(0.0), vec2(1.0)) * cropB.zw);
    float k = smoothstep(0.0, 1.0, inside);
    vec4 c = mix(a, b, k);
    // The rim: a thin bright line at the front, strongest facing the notch.
    float rim = exp(-pow((r - dist) / (band * 0.12), 2.0)) * sin(3.14159265 * t);
    float facing = 0.55 + 0.45 * clamp(-dir.y * 0.5 + 0.5, 0.0, 1.0);
    c.rgb += vec3(rim * 0.22 * facing);
    // A breath of darkening just outside the front, so the new picture reads
    // as arriving on top (a shadow under glass).
    float shade = exp(-pow((dist - r) / (band * 0.5), 2.0)) * step(r, dist) * sin(3.14159265 * t);
    c.rgb *= 1.0 - 0.10 * shade;
    fragColor = vec4(c.rgb, c.a) * qt_Opacity;
}
