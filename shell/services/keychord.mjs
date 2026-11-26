// @ts-check

/** A shortcut as kuwai.palette(true) gives it. @typedef {{ id?: string, kind?: string, group?: string, text?: string, keys?: string, aid?: string, def?: string, custom?: boolean, fixed?: boolean }} Entry */
/** A bind as `hyprctl binds -j` gives it. @typedef {{ modmask?: number, key?: string, keycode?: number, submap?: string, mouse?: boolean, description?: string }} Live */
/** A pressed chord. @typedef {{ keys: string, canon: string, why: string }} Chord */
/** What holds a chord. @typedef {{ kind: string, entry: Entry | null, text: string }} Conflict */

const SHIFT = 0x02000000, CTRL = 0x04000000, ALT = 0x08000000, META = 0x10000000;
const MODS = ["SUPER", "CTRL", "ALT", "SHIFT"];
const MOD_NAMES = /** @type {Record<string, string>} */ ({ SUPER: "SUPER", WIN: "SUPER", LOGO: "SUPER", MOD4: "SUPER", META: "SUPER",
    CTRL: "CTRL", CONTROL: "CTRL", ALT: "ALT", MOD1: "ALT", SHIFT: "SHIFT" });

const NAMED = /** @type {Record<number, string>} */ ({
    0x01000000: "Escape", 0x01000001: "Tab", 0x01000002: "Tab", 0x01000003: "BackSpace", 0x01000004: "Return", 0x01000005: "Return",
    0x01000006: "Insert", 0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print", 0x01000010: "Home", 0x01000011: "End",
    0x01000012: "left", 0x01000013: "up", 0x01000014: "right", 0x01000015: "down", 0x01000016: "Prior", 0x01000017: "Next",
    0x01000055: "Menu", 0x20: "space", 0x2c: "comma", 0x2d: "minus", 0x2e: "period", 0x2f: "slash", 0x3b: "semicolon", 0x3d: "equal",
    0x5b: "bracketleft", 0x5c: "backslash", 0x5d: "bracketright", 0x60: "grave", 0x27: "apostrophe",
    0x3c: "comma", 0x3e: "period", 0x3f: "slash", 0x3a: "semicolon", 0x2b: "equal", 0x5f: "minus", 0x7b: "bracketleft",
    0x7d: "bracketright", 0x7c: "backslash", 0x7e: "grave", 0x22: "apostrophe"
});
const MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01000025, 0x01000026, 0x01000053, 0x01000054, 0x01000056, 0x01000057, 0x01001103];
const BARE_OK = /^(F\d{1,2}|Print|Pause)$/;

/**
 * The chord a key press makes, in Hyprland's words. Digits are bound by
 * keycode (code:10…19), the way the workspace keys are, so they hold on any
 * layout. null: a modifier on its own (keep listening).
 * @param {number} key Qt's key @param {number} modifiers Qt's modifiers @param {number} [scan] the xkb keycode
 * @returns {Chord | null}
 */
export function chordOf(key, modifiers, scan) {
    if (MODIFIER_KEYS.includes(key)) return null;
    const mods = [];
    if (modifiers & META) mods.push("SUPER");
    if (modifiers & CTRL) mods.push("CTRL");
    if (modifiers & ALT) mods.push("ALT");
    if (modifiers & SHIFT) mods.push("SHIFT");
    let name = "";
    const sc = Number(scan) || 0;
    if (sc >= 10 && sc <= 19) name = "code:" + sc;
    else if (key >= 0x41 && key <= 0x5a) name = String.fromCharCode(key);
    else if (key >= 0x30 && key <= 0x39) name = "code:" + (key === 0x30 ? 19 : key - 0x31 + 10);
    else if (key >= 0x01000030 && key <= 0x01000047) name = "F" + (key - 0x01000030 + 1);
    else name = NAMED[key] || "";
    if (!name) return { keys: "", canon: "", why: "That key can't be a shortcut" };
    const keys = mods.concat([name]).join(" + ");
    const plain = !mods.some(m => m !== "SHIFT");
    if (plain && !BARE_OK.test(name)) return { keys, canon: canon(keys), why: "Add Super, Ctrl or Alt" };
    return { keys, canon: canon(keys), why: "" };
}

/**
 * One spelling per chord, whatever the order of its modifiers or how its
 * digit is written ("SHIFT + SUPER + 1" and "SUPER + SHIFT + code:10" meet).
 * @param {string | undefined} keys @returns {string}
 */
export function canon(keys) {
    const mods = new Set();
    let key = "";
    for (const part of String(keys || "").split("+")) {
        const p = part.trim().toUpperCase();
        if (MOD_NAMES[p]) mods.add(MOD_NAMES[p]);
        else if (p) key = p;
    }
    if (/^[0-9]$/.test(key)) key = "CODE:" + (key === "0" ? 19 : Number(key) + 9);
    return MODS.filter(m => mods.has(m)).concat([key]).join("+");
}

/** A live bind's chord, in canon's spelling. @param {Live} b @returns {string} */
export function canonLive(b) {
    const m = Number(b.modmask) || 0;
    const mods = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]].filter(([bit]) => m & /** @type {number} */ (bit)).map(([, n]) => n);
    const key = b.keycode ? "code:" + b.keycode : String(b.key || "");
    return canon(mods.concat([key]).join(" + "));
}

/**
 * Who has this chord now, other than the action being changed: another of
 * kuwai's actions (it can be moved off), something else (your own config, a
 * hold key: it can't), or the action itself.
 * @param {string} chord canon of the new chord @param {string} aid the action being changed
 * @param {Entry[]} entries @param {Live[]} live @returns {Conflict | null}
 */
export function conflict(chord, aid, entries, live) {
    if (!chord) return null;
    const mine = entries.find(e => e.aid === aid);
    if (mine && mine.keys && canon(mine.keys) === chord) return { kind: "same", entry: mine, text: mine.text || "" };
    const other = entries.find(e => e.aid !== aid && e.keys && canon(e.keys) === chord);
    if (other) return { kind: other.fixed ? "other" : "kuwai", entry: other, text: other.text || "" };
    for (const b of live || []) {
        if (b.submap || b.mouse || canonLive(b) !== chord) continue;
        const m = /^\[([^\]]+)\]\s*(.*)$/.exec(String(b.description || ""));
        const desc = m ? m[2] : String(b.description || "");
        const owner = entries.find(e => m && e.group === m[1] && e.text === desc);
        if (owner && owner.aid === aid) continue;
        if (owner && !owner.fixed) return { kind: "kuwai", entry: owner, text: owner.text || "" };
        return { kind: "other", entry: null, text: desc };
    }
    return null;
}

/**
 * The actions in groups, in the Shortcuts panel's order, narrowed by every
 * word of the filter (name, group, keys).
 * @param {Entry[]} entries @param {string} filter
 * @returns {{ group: string, items: (Entry & { sub: string })[] }[]}
 */
export function groupsOf(entries, filter) {
    const order = ["Shell", "Launch", "Windows", "Columns", "Workspaces", "Screens", "Capture", "Dictation", "Apps", "Media", "Hardware", "Zoom", "Pickers", "Theming", "Utilities"];
    const words = String(filter || "").toLowerCase().split(/\s+/).filter(w => w);
    /** @type {Record<string, (Entry & { sub: string })[]>} */
    const by = {};
    /** @type {string[]} */
    const names = [];
    for (const e of entries || []) {
        if (e.kind && e.kind !== "bind") continue;
        const parts = String(e.group || "Other").split("|");
        const hay = [e.text, e.group, e.keys, e.def].join(" ").toLowerCase();
        if (!words.every(w => hay.includes(w))) continue;
        if (!by[parts[0]]) { by[parts[0]] = []; names.push(parts[0]); }
        by[parts[0]].push(Object.assign({ sub: parts.slice(1).join(" · ") }, e));
    }
    /** @param {string} g */
    const rank = g => { const i = order.indexOf(g); return i < 0 ? 50 : i; };
    return names.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b)).map(g => ({ group: g, items: by[g] }));
}

/**
 * A chord as caps to draw: "SUPER + SHIFT + code:10" → Super, Shift, 1.
 * @param {string | undefined} keys @returns {string[]}
 */
export function caps(keys) {
    const names = /** @type {Record<string, string>} */ ({ SUPER: "Super", CTRL: "Ctrl", CONTROL: "Ctrl", ALT: "Alt", SHIFT: "Shift",
        RETURN: "↩", ESCAPE: "esc", DELETE: "Del", BACKSPACE: "⌫", TAB: "⇥", SPACE: "Space", LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓",
        GRAVE: "`", SLASH: "/", BACKSLASH: "\\", COMMA: ",", PERIOD: ".", EQUAL: "=", MINUS: "−", BRACKETLEFT: "[", BRACKETRIGHT: "]",
        SEMICOLON: ";", APOSTROPHE: "'", PRIOR: "PgUp", NEXT: "PgDn", PRINT: "PrtSc" });
    return String(keys || "").split("+").map(k => k.trim()).filter(k => k).map(k => {
        const code = /^code:(\d+)$/i.exec(k);
        if (code && Number(code[1]) >= 10 && Number(code[1]) <= 19) return String((Number(code[1]) - 9) % 10);
        return names[k.toUpperCase()] || (k.length === 1 ? k.toUpperCase() : k);
    });
}
