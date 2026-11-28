const KUWAIN = new Set(["notifs", "bar", "mode", "center", "launcher", "island", "capsule", "feature", "backup"]);
const EXTN = new Set(["capsule", "providers"]);

/** @param {unknown} argv @param {string} bin */
export function safeRun(argv, bin) {
    if (!Array.isArray(argv) || !argv.length || argv.length > 16) return null;
    if (!argv.every(x => typeof x === "string" && x.length > 0 && x.length < 512 && !x.includes("\0"))) return null;
    const kuwai = bin + "/kuwai";
    const ext = bin + "/kuwai-ext";
    const lead = String(argv[0]);
    if (lead === kuwai || lead === "kuwai") {
        const sub = String(argv[1] || "");
        return KUWAIN.has(sub) ? argv.map(String) : null;
    }
    if (lead === ext || lead === "kuwai-ext") {
        const sub = String(argv[1] || "");
        return EXTN.has(sub) ? argv.map(String) : null;
    }
    return null;
}