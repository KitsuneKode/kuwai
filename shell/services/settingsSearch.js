.pragma library
// Search explicit settings metadata; no UI source parsing or instantiation.

// What matches q, best first: rows whose words hold every word of q (a
// label match counts most), then pages whose name or keywords do that no
// row of theirs already answered.
//   → [{ section, row: { label, detail, group } | null }]
function search(sections, rows, q, limit) {
    const words = String(q || "").toLowerCase().trim().split(/\s+/).filter(w => w.length > 0);
    if (!words.length || (words.length === 1 && words[0].length < 2)) return [];
    const bySection = {};
    for (const s of sections) bySection[s.id] = s;
    const out = [];
    for (const r of rows) {
        const s = bySection[r.page];
        if (!s) continue;
        // Each word in the row itself, or in its page's name and keywords
        // ("lock screen": Lock is a row of the page about the screen), but
        // at least one in the row, so one word never lists a whole page.
        const page = (s.label + " " + (s.keys || "")).toLowerCase();
        const lab = r.label.toLowerCase();
        let score = 0, own = 0, ok = true;
        for (const w of words) {
            if (lab.startsWith(w)) { score += 6; own++; }
            else if (lab.includes(w)) { score += 4; own++; }
            else if (r.words.includes(w)) { score += 1; own++; }
            else if (page.includes(w)) score += 0.3;
            else { ok = false; break; }
        }
        if (!ok || !own) continue;
        if (lab.includes(words[0])) score += 1;          // what you typed first is what you mean most
        out.push({ section: s, row: { label: r.label, detail: r.detail, group: r.group }, score });
    }
    // The page itself too, when its name or keywords hold every word; first
    // when its name is what you typed.
    for (const s of sections) {
        const hay = (s.label + " " + (s.keys || "")).toLowerCase();
        if (!words.every(w => hay.includes(w))) continue;
        const name = s.label.toLowerCase();
        const score = words.reduce((n, w) => n + (name.includes(w) ? 5 : 1.5), 0) + (name.startsWith(words[0]) ? 4 : 0);
        out.push({ section: s, row: null, score });
    }
    out.sort((a, b) => b.score - a.score);
    return out.slice(0, limit || 12).map(r => ({ section: r.section, row: r.row }));
}
