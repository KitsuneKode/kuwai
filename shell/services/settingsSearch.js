.pragma library
// Finding a setting by what it's called or what it does: the Settings
// panel's own rows, read from its source (modules/island/SettingsPanel.qml),
// so the index can't drift from what the panel shows and no page has to be
// built to be searched. (services/SettingsIndex; tested in
// tests/shell/settings-search.test.mjs.)

// The rows of each page: [{ page, label, detail, group, words }].
//   src    SettingsPanel.qml's text
//   pages  { barPage: "bar", … }: a page Component's id → its section id
function parseRows(src, pages) {
    const rows = [];
    const text = String(src || "");
    // Each page: from `id: xxxPage` to the next page's.
    const marks = [];
    const re = /\bid:\s*(\w+Page)\b/g;
    let m;
    while ((m = re.exec(text))) if (pages[m[1]]) marks.push({ id: m[1], at: m.index });
    for (let i = 0; i < marks.length; i++) {
        const chunk = text.slice(marks[i].at, i + 1 < marks.length ? marks[i + 1].at : text.length);
        const page = pages[marks[i].id];
        // Group titles in order, so a row knows the group it sits under.
        const titles = [];
        const tre = /(?:^|[;\n])\s*title:\s*"([^"]+)"/g;
        let t;
        while ((t = tre.exec(chunk))) titles.push({ at: t.index, title: t[1] });
        const starts = [];
        const rre = /\bSettingsRow\s*\{/g;
        let r;
        while ((r = rre.exec(chunk))) starts.push(r.index);
        for (let j = 0; j < starts.length; j++) {
            const at = starts[j];
            const body = chunk.slice(at, j + 1 < starts.length ? starts[j + 1] : chunk.length);
            // The row's own label (a line or a `;` starts it; an option's
            // label sits after `{ id: …,` and doesn't count).
            const lab = /(?:^|[;\n])\s*label:\s*"([^"]+)"/.exec(body);
            if (!lab) continue;              // a row built from data (reminders): nothing fixed to find
            const det = /(?:^|[;\n])\s*detail:\s*(?:[^"\n]*\?\s*)?"([^"]+)"/.exec(body);
            // Its choices' names find it too ("Notch" finds Shape).
            const opts = [];
            const ore = /\{\s*id:\s*"[^"]*",\s*label:\s*"([^"]+)"\s*\}/g;
            let o;
            while ((o = ore.exec(body))) opts.push(o[1]);
            let group = "";
            for (const g of titles) if (g.at < at) group = g.title;
            rows.push({ page, label: lab[1], detail: det ? det[1] : "", group,
                        words: [lab[1], det ? det[1] : "", opts.join(" "), group].join(" ").toLowerCase() });
        }
    }
    return rows;
}

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
        const hay = r.words + " " + s.label.toLowerCase();
        if (!words.every(w => hay.includes(w))) continue;
        const lab = r.label.toLowerCase();
        let score = 0;
        for (const w of words) score += lab.startsWith(w) ? 6 : lab.includes(w) ? 4 : r.words.includes(w) ? 1 : 0.5;
        out.push({ section: s, row: { label: r.label, detail: r.detail, group: r.group }, score });
    }
    const answered = {};
    for (const r of out) answered[r.section.id] = true;
    for (const s of sections) {
        const hay = (s.label + " " + (s.keys || "")).toLowerCase();
        if (!words.every(w => hay.includes(w))) continue;
        const score = words.reduce((n, w) => n + (s.label.toLowerCase().includes(w) ? 5 : 1.5), 0);
        // The page itself, above its rows when its name is what you typed.
        if (!answered[s.id] || s.label.toLowerCase().includes(words.join(" ")))
            out.push({ section: s, row: null, score: score + (answered[s.id] ? 1 : 0) });
    }
    out.sort((a, b) => b.score - a.score);
    return out.slice(0, limit || 12).map(r => ({ section: r.section, row: r.row }));
}
