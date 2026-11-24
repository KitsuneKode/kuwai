import { useState } from "react";
import { MotionConfig, motion } from "motion/react";

type Category = "all" | "architecture" | "craft" | "resilience";

const FILTERS: { id: Category; label: string }[] = [
  { id: "all", label: "All upgrades" },
  { id: "architecture", label: "Architecture" },
  { id: "craft", label: "Craft and motion" },
  { id: "resilience", label: "Memory and speed" }
];

const UPGRADES: { cat: Exclude<Category, "all">; metric: string; title: string; body: string; proof: string }[] = [
  {
    cat: "craft",
    metric: "0 / 0 / 0 / 0 / 0",
    title: "Every surface driven by one token & easing system",
    body: "Replaced 297 hardcoded sizes, durations, and hex values plus all 74 literal Qt easings with one design token table and cubic-bezier curve set that scales cleanly up to 200% text size.",
    proof: "Automated token & easing gate"
  },
  {
    cat: "craft",
    metric: "1 draw call",
    title: "Single-pass SDF liquid glass & zero-Hz hover",
    body: "GlassCard renders tint, outer dark ring, top sheen, directional top-left/bottom-right specular rim, and procedural grain in one compiled .qsb shader pass, while FluidHighlight tracks geometry signals at 0 Hz when stationary.",
    proof: "glasscard.frag.qsb · 7 wakeups/s"
  },
  {
    cat: "architecture",
    metric: "0 layer leaks",
    title: "Pure .mjs state machines & strict UI boundaries",
    body: "Extracted unit-tested reducers for overlays, settings writes, island proximity, and audio/DAC hotplugs (515+ Bun tests), drove component-to-service imports to 0/0/0, and wired keyring-backed T3 approvals right into the notch.",
    proof: "kuwai-layers 0/0/0 · 515 Bun tests"
  },
  {
    cat: "resilience",
    metric: "1.1 s recovery",
    title: "Supervised shell with zero orphaned helpers",
    body: "Running kuwai as a dedicated user service with strict child teardown eliminated 127 lingering background processes and recovers automatically from crashes.",
    proof: "Automatic fallback session"
  },
  {
    cat: "architecture",
    metric: "11 themes",
    title: "Standalone atomic theming engine",
    body: "Switch palettes and wallpapers atomically with built-in WCAG contrast verification, custom templates, and zero third-party theme framework lock-in.",
    proof: "Single-writer palette swap"
  },
  {
    cat: "resilience",
    metric: "161 MB idle",
    title: "Static optical fonts, gated daemons & clean idle",
    body: "Static Inter and SF Pro optical cuts, conditional startup for optional daemons, FileView-watched package status, and pruned caches bring the live shell down to 161 MB RSS and 0% idle CPU.",
    proof: "Live kuwai-check budget"
  },
  {
    cat: "craft",
    metric: "138 frames",
    title: "Zero-warning visual rehearsal before every release",
    body: "Every island panel is rendered across 100%, 120%, and 200% text scales with automated contrast, clipping, and type-scale verification before updates reach the stable channel.",
    proof: "0 wrong · 0 notices"
  },
  {
    cat: "architecture",
    metric: "10 providers",
    title: "Live quota awareness & inline approvals across agents",
    body: "Tracks Claude, OpenAI Codex, Antigravity, Cursor, Grok, Gemini, and multi-profile Devin accounts in one calm reset countdown — with inline Allow/Deny for waiting T3 and terminal agents.",
    proof: "Keyring-first local discovery"
  }
];

export default function UpgradeList() {
  const [filter, setFilter] = useState<Category>("all");
  const visible = filter === "all" ? UPGRADES : UPGRADES.filter((u) => u.cat === filter);

  return (
    <MotionConfig reducedMotion="user">
      <div className="segmented" role="tablist" aria-label="Filter shipped upgrades">
        {FILTERS.map((f) => {
          const active = filter === f.id;
          return (
            <button
              key={f.id}
              type="button"
              role="tab"
              className="segment-tab"
              aria-selected={active}
              onClick={() => setFilter(f.id)}
            >
              {active && (
                <motion.span
                  layoutId="upgrade-filter-pill"
                  className="segment-pill"
                  transition={{ type: "spring", stiffness: 520, damping: 38 }}
                />
              )}
              {f.label}
            </button>
          );
        })}
      </div>

      <div className="upgrade-list">
        {visible.map((u) => (
          <article className="upgrade-row" key={u.title}>
            <div className="upgrade-metric tabular">{u.metric}</div>
            <div className="upgrade-main">
              <h3>{u.title}</h3>
              <p>{u.body}</p>
            </div>
            <div className="upgrade-proof">{u.proof}</div>
          </article>
        ))}
      </div>
    </MotionConfig>
  );
}
