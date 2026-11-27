export function linear(v) {
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

export function grey(lum) {
    const l = Math.max(0, Math.min(1, lum));
    return l <= 0.0031308 ? l * 12.92 : 1.055 * Math.pow(l, 1 / 2.4) - 0.055;
}

export function ratio(a, b) {
    const la = linear(a), lb = linear(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

export function ground(bright, o, plate) {
    const scrimmed = Math.max(0, Math.min(1, bright)) * (1 - o.scrim);
    const plated = scrimmed * (1 - plate) + o.tone * plate;
    return plated * (1 - o.frost) + o.frost;
}

export function reads(bright, o, plate) {
    const bg = ground(bright, o, plate);
    return o.inks.every(ink => {
        const tone = ink.tone === undefined ? 1 : ink.tone;
        return ratio(ink.alpha * tone + bg * (1 - ink.alpha), bg) >= ink.want;
    });
}

export function plateFor(bright, o) {
    const step = o.step || 0.02;
    for (let p = 0; p <= o.most + 1e-6; p += step) if (reads(bright, o, p)) return Math.round(p * 100) / 100;
    return o.most;
}

export function zoneOf(box, width, height) {
    if (!box || !(width > 0) || !(height > 0)) return { x: 0, y: 0, width: 1, height: 1 };
    const x = Math.max(0, Math.min(1, box.x / width)), y = Math.max(0, Math.min(1, box.y / height));
    return {
        x: x, y: y,
        width: Math.max(1 / 32, Math.min(1 - x, box.width / width)),
        height: Math.max(1 / 18, Math.min(1 - y, box.height / height))
    };
}

export function cells(z, width, height) {
    const x = Math.max(0, Math.min(width - 1, Math.floor(z.x * width)));
    const y = Math.max(0, Math.min(height - 1, Math.floor(z.y * height)));
    return {
        x: x, y: y,
        width: Math.max(1, Math.min(width - x, Math.ceil(z.width * width))),
        height: Math.max(1, Math.min(height - y, Math.ceil(z.height * height)))
    };
}

export function brightest(rgba) {
    const tones = [];
    for (let i = 0; i + 2 < rgba.length; i += 4) tones.push(Math.max(rgba[i], rgba[i + 1], rgba[i + 2]) / 255);
    tones.sort((a, b) => a - b);
    return tones.length ? tones[Math.min(tones.length - 1, Math.floor(tones.length * 0.95))] : 0;
}
