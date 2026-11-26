pragma Singleton

// What the agents spent (bin/kuwai-spend: tokens per provider per day from the
// logs Claude Code, Codex and opencode write on this machine, priced from
// lib/spend-prices.json: list prices, an estimate). Nothing leaves the machine.
// The helper runs only while the Usage panel shows it (`wanted`) and reads only
// what the logs gained since its last read; with the panel closed it isn't
// running at all.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "spendreport.mjs" as SpendReport

Singleton {
    id: root
    property bool wanted: false
    // { claude: { today: { tokens, cost, priced }, week: {…} }, codex: … }
    property var providers: ({})
    property string pricesAsOf: ""
    property bool loaded: false
    // A Usage card's provider (its driver: "claude", "claudeAgent", "codex"…) → the logs it keeps.
    function key(id) { const s = String(id || "").toLowerCase(); return /claude/.test(s) ? "claude" : /codex/.test(s) ? "codex" : /opencode/.test(s) ? "opencode" : s; }
    function of(id) { return providers[key(id)] || null; }
    // As lib/spend.mjs tokensText (the shell's tree doesn't import lib/).
    function tokens(n) {
        n = n || 0;
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e8 ? 0 : 1) + "M";
        if (n >= 1e3) return Math.round(n / 1e3) + "K";
        return String(Math.round(n));
    }
    // "Today 1.2M tokens · ~$3.40 · 7 days ~$21" (no price: tokens only)
    function line(id) {
        const p = of(id);
        if (!p || (!p.today.tokens && !p.week.tokens)) return "";
        const money = v => "~" + SpendReport.money(v);
        const today = !p.today.tokens ? "Nothing today"
            : "Today " + tokens(p.today.tokens) + " tokens" + (p.today.priced && p.today.cost > 0 ? " · " + money(p.today.cost) : "");
        const week = "7 days " + (p.week.priced && p.week.cost > 0 ? money(p.week.cost) : tokens(p.week.tokens) + " tokens");
        return today + " · " + week;
    }

    Process {
        running: root.wanted
        command: ["setpriv", "--pdeathsig", "KILL", "--", "sh", "-c",
                  'command -v bun >/dev/null 2>&1 && exec bun "$1" --watch; exec node "$1" --watch', "kuwai-spend", Paths.bin + "/kuwai-spend"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const o = JSON.parse(data);
                    root.providers = o.providers || ({});
                    root.pricesAsOf = o.pricesAsOf || "";
                    root.loaded = true;
                } catch (e) {}
            }
        }
    }
}
