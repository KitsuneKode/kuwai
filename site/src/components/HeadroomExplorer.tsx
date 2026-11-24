import { useState } from "react";
import { MotionConfig, motion } from "motion/react";

type SliceKey = "voxtype" | "shell" | "hyprland" | "docker" | "easyeffects" | "other";

const SLICES: {
  key: SliceKey;
  label: string;
  mb: number;
  cls: string;
  headline: string;
  sub: string;
  delta: string;
}[] = [
  {
    key: "voxtype",
    label: "Speech model (active vs idle)",
    mb: 1456,
    cls: "seg-vox",
    headline: "Speech model: 1,456 MB active (18 MB idle after fp16 + idle unload)",
    sub: "Upgrading Parakeet from fp32 (3,123 MB) to fp16 with a 120 s idle unload already reclaimed over 3 GB at rest. Moving inference into an on-demand worker lets the dGPU enter full runtime suspend, while int8 stays the fast path for CPU-only Linux laptops.",
    delta: "18 MB at rest · dGPU sleep next"
  },
  {
    key: "shell",
    label: "Desktop shell",
    mb: 469,
    cls: "seg-shell",
    headline: "Desktop shell: 469 MB on dev channel",
    sub: "Fresh stable launches start near 207 MB; cooling heavy panel loaders on close targets under 300 MB across long sessions.",
    delta: "~-170 MB"
  },
  {
    key: "hyprland",
    label: "Compositor",
    mb: 396,
    cls: "seg-hypr",
    headline: "Hyprland compositor: 396 MB",
    sub: "Core Wayland compositor and GPU framebuffers across dual high-refresh displays.",
    delta: "Essential baseline"
  },
  {
    key: "docker",
    label: "Local containers",
    mb: 300,
    cls: "seg-docker",
    headline: "Docker and local search: 300 MB at boot",
    sub: "Currently launched eagerly at login even when idle. Switching to socket activation drops boot cost to zero.",
    delta: "-300 MB at boot"
  },
  {
    key: "easyeffects",
    label: "Audio DSP",
    mb: 170,
    cls: "seg-audio",
    headline: "Audio processing pipeline: 170 MB",
    sub: "Optional speaker EQ and microphone cleanup, enabled per hardware profile.",
    delta: "Optional service"
  },
  {
    key: "other",
    label: "Auth, usage, helpers",
    mb: 382,
    cls: "seg-other",
    headline: "Polkit prompt, quota watcher, legacy daemons: 382 MB",
    sub: "Includes the software-rendered polkit prompt (94 MB), usage watcher (85 MB), and remaining legacy tray applets we are retiring.",
    delta: "~-120 MB"
  }
];

export default function HeadroomExplorer() {
  const [view, setView] = useState<"bottlenecks" | "roadmap">("bottlenecks");
  const [hovered, setHovered] = useState<SliceKey | null>(null);
  const [locked, setLocked] = useState<SliceKey | null>(null);

  const activeKey = hovered ?? locked;
  const activeSlice = SLICES.find((s) => s.key === activeKey);

  return (
    <MotionConfig reducedMotion="user">
      <div className="segmented" role="tablist" aria-label="Headroom and roadmap views">
        {(
          [
            ["bottlenecks", "Measured headroom"],
            ["roadmap", "What ships next"]
          ] as const
        ).map(([id, label]) => {
          const active = view === id;
          return (
            <button
              key={id}
              type="button"
              role="tab"
              className="segment-tab"
              aria-selected={active}
              onClick={() => setView(id)}
            >
              {active && (
                <motion.span
                  layoutId="headroom-tab-pill"
                  className="segment-pill"
                  transition={{ type: "spring", stiffness: 520, damping: 38 }}
                />
              )}
              {label}
            </button>
          );
        })}
      </div>

      {view === "bottlenecks" ? (
        <div className="improve-panel">
          <div className="ram-card">
            <div className="ram-top">
              <div>
                <h3>
                  {activeSlice
                    ? activeSlice.headline
                    : "Active session footprint: 3.17 GB active (1.74 GB idle) vs 1.25 GB target"}
                </h3>
                <p className="ram-sub">
                  {activeSlice
                    ? activeSlice.sub
                    : "Hover or select any segment to inspect where desktop memory goes and what the next architectural levers reclaim."}
                </p>
              </div>
              <div className="ram-delta tabular">
                {activeSlice ? activeSlice.delta : "-1.9 GB + dGPU sleep"}
              </div>
            </div>

            <div className={`linked-bar${activeKey ? " has-active" : ""}`} role="group" aria-label="Boot memory breakdown">
              {SLICES.map((s) => (
                <button
                  key={s.key}
                  type="button"
                  className={`bar-seg ${s.cls}${activeKey === s.key ? " is-active" : ""}`}
                  style={{ flexGrow: s.mb }}
                  aria-label={`${s.label} ${s.mb} MB`}
                  onMouseEnter={() => setHovered(s.key)}
                  onMouseLeave={() => setHovered(null)}
                  onClick={() => setLocked((prev) => (prev === s.key ? null : s.key))}
                />
              ))}
            </div>

            <div className="linked-legend">
              {SLICES.map((s) => (
                <button
                  key={s.key}
                  type="button"
                  className={`legend-item${activeKey === s.key ? " is-active" : ""}`}
                  onMouseEnter={() => setHovered(s.key)}
                  onMouseLeave={() => setHovered(null)}
                  onClick={() => setLocked((prev) => (prev === s.key ? null : s.key))}
                >
                  <span className={`legend-swatch ${s.cls}`} aria-hidden="true" />
                  <span className="legend-name">{s.label}</span>
                  <span className="legend-val tabular">{s.mb.toLocaleString()} MB</span>
                </button>
              ))}
            </div>
          </div>

          <div className="table-wrap">
            <table className="headroom-table">
              <thead>
                <tr>
                  <th>Area</th>
                  <th>Measured today</th>
                  <th>Target</th>
                  <th>How we get there</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td><strong>Idle memory &amp; dGPU sleep</strong></td>
                  <td className="tabular">18 MB idle RAM, dGPU stays active</td>
                  <td className="tabular target-good">dGPU suspended + 1.25 GB idle</td>
                  <td>Move speech inference into an on-demand worker so CUDA releases the card, socket-activate containers, and cool closed panel loaders.</td>
                </tr>
                <tr>
                  <td><strong>Idle GPU wakeups</strong></td>
                  <td className="tabular target-good">Shipped · 7 wakeups/s (0 Hz hover)</td>
                  <td className="tabular target-good">Enforced in kuwai-check</td>
                  <td>FluidHighlight now tracks ancestor geometry and swipe transforms via Qt.callLater, and audio peak capture pauses when hidden, locked, or under reduced motion.</td>
                </tr>
                <tr>
                  <td><strong>Standalone portability</strong></td>
                  <td className="tabular">33 non-adapter HyDE hooks left</td>
                  <td className="tabular target-good">Clean Arch VM install</td>
                  <td>Personal DAC/GPS/hwmon defaults removed and optional daemons gated; isolating the remaining HyDE hooks into the 5 adapters finishes clean-VM portability.</td>
                </tr>
                <tr>
                  <td><strong>State reliability</strong></td>
                  <td className="tabular target-good">Shipped · 4 pure .mjs reducers</td>
                  <td className="tabular target-good">100% pure component layers</td>
                  <td>Overlay lifecycle (Center, Clipboard, Assistant), Settings writes, Island proximity, and Osd DAC hotplugs now run on Bun-tested reducers with 0/0/0 layer leaks.</td>
                </tr>
                <tr>
                  <td><strong>Login transition</strong></td>
                  <td className="tabular">2.8 s compositor handover</td>
                  <td className="tabular target-good">One continuous reveal</td>
                  <td>Mask greeter background audio services, decode at native monitor resolution, and finish with a 400 ms boot reveal.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        <div className="improve-panel">
          <div className="roadmap-grid">
            <div className="roadmap-item">
              <h3>Live Activities from terminal panes</h3>
              <p>Stream long test suites, builds, and CI runs into the notch with real progress and a single-click jump when they finish.</p>
            </div>
            <div className="roadmap-item">
              <h3>Overnight digest on return</h3>
              <p>Welcome back returning sessions with one concise summary of finished agents, waiting approvals, and green pull requests.</p>
            </div>
            <div className="roadmap-item">
              <h3>Installable Quickshell component registry</h3>
              <p>Install individual glass primitives like the notch or gliding highlight into any existing Quickshell setup with one command.</p>
            </div>
            <div className="roadmap-item">
              <h3>Portable snapshots and package rollback</h3>
              <p>Export explicit packages, monitor layouts, and theme preferences to reproduce a machine, and roll back upgrades cleanly from cache.</p>
            </div>
            <div className="roadmap-item">
              <h3>Drop shelf to your phone</h3>
              <p>Drag files directly onto the notch to stash temporarily or send over KDE Connect with a live transfer progress ring.</p>
            </div>
            <div className="roadmap-item">
              <h3>Zero-setup demo mode</h3>
              <p>Preview realistic agent approvals, quota resets, and media states in one command before wiring any local hooks.</p>
            </div>
          </div>
        </div>
      )}
    </MotionConfig>
  );
}
