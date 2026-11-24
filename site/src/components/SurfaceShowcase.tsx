import { useState } from "react";
import { AnimatePresence, MotionConfig, motion } from "motion/react";

type SurfaceKey = "primitives" | "login" | "alarms" | "updates";

const SURFACES: Record<
  SurfaceKey,
  {
    label: string;
    src: string;
    alt: string;
    heading: string;
    desc: string;
    specs: [string, string][];
  }
> = {
  primitives: {
    label: "Primitives gallery",
    src: "/assets/kuwai/primitives.png",
    alt: "kuwai UI primitives gallery showing buttons, notices, meters, toggles, and control tiles",
    heading: "One visual grammar across every surface",
    desc: "Buttons, notices, meters, toggles, and Control Center tiles inherit the exact same liquid-glass tokens, 140 ms press response, keyboard focus rings, and screen-reader roles.",
    specs: [
      ["Typography", "Inter optical sizes by default, upgrading automatically to SF Pro when present"],
      ["Motion", "Critically damped springs with FreeType native glyph rendering"],
      ["Accessibility", "200% text scaling, high-contrast surfaces, and fade-only reduced motion"]
    ]
  },
  login: {
    label: "Login and lock",
    src: "/assets/kuwai/login.webp",
    alt: "kuwai greetd login screen with centered clock, avatar, and hold-to-power actions",
    heading: "Login and lock cut from the same cloth",
    desc: "A root-owned greeter mirrors your display geometry and keyboard layout from your last session. Password entry pulses five dots without revealing length, and power actions require a deliberate hold.",
    specs: [
      ["Privilege boundary", "Greeter code stays root-owned; monitor layout is read as validated plain data"],
      ["Adaptive contrast", "Solves clock ink contrast against the actual wallpaper crop before painting"],
      ["Lock resilience", "Stays locked across shell crashes and recovers cleanly across monitor hot-plugs"]
    ]
  },
  alarms: {
    label: "Island cards",
    src: "/assets/kuwai/island-alarm-cards.gif",
    alt: "Animated recording of kuwai alarm, reminder, and timer cards growing out of the island",
    heading: "Cards that grow out of the notch when needed",
    desc: "Alarms, due reminders, finished timers, and connecting audio devices grow out of the top edge with ordered text entrances and stay answerable right from the lock screen.",
    specs: [
      ["Wake support", "Wakes a sleeping laptop for scheduled alarms through systemd WakeSystem"],
      ["Direct control", "Snooze, stop, repeat, or dismiss by pointer or a single keyboard chord"],
      ["Quiet under motion limits", "Reduced motion keeps color and fade while disabling travel and stagger"]
    ]
  },
  updates: {
    label: "Software updates",
    src: "/assets/kuwai/island-states-sheet.png",
    alt: "Seventeen-second contact sheet showing kuwai software update check, error recovery, and completion",
    heading: "Detached system updates with build-diff review",
    desc: "Official Arch updates apply together under one authentication prompt, while AUR packages show their PKGBUILD diff and community standing before building as an unprivileged user.",
    specs: [
      ["Detached execution", "Runs in its own systemd unit so shell restarts never interrupt package installs"],
      ["Lean storage", "Strips debug bloat automatically and caps retained build artifacts at 1 GiB"],
      ["Post-update awareness", "Flags kernel restarts and surfaces .pacnew configuration diffs"]
    ]
  }
};

const KEYS: SurfaceKey[] = ["primitives", "login", "alarms", "updates"];

export default function SurfaceShowcase() {
  const [selected, setSelected] = useState<SurfaceKey>("primitives");
  const current = SURFACES[selected];

  return (
    <MotionConfig reducedMotion="user">
      <div className="surface-switcher">
        <div className="segmented" role="tablist" aria-label="Captured kuwai surfaces">
          {KEYS.map((key) => {
            const active = selected === key;
            return (
              <button
                key={key}
                type="button"
                role="tab"
                className="segment-tab"
                aria-selected={active}
                onClick={() => setSelected(key)}
              >
                {active && (
                  <motion.span
                    layoutId="surface-tab-pill"
                    className="segment-pill"
                    transition={{ type: "spring", stiffness: 520, damping: 38 }}
                  />
                )}
                {SURFACES[key].label}
              </button>
            );
          })}
        </div>

        <div className="surface-stage">
          <div className="surface-visual">
            <AnimatePresence mode="wait">
              <motion.img
                key={selected}
                src={current.src}
                alt={current.alt}
                initial={{ opacity: 0, scale: 0.985 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.99 }}
                transition={{ duration: 0.18 }}
              />
            </AnimatePresence>
          </div>
          <div className="surface-notes">
            <h3>{current.heading}</h3>
            <p>{current.desc}</p>
            <dl className="spec-pairs">
              {current.specs.map(([dt, dd]) => (
                <div key={dt}>
                  <dt>{dt}</dt>
                  <dd>{dd}</dd>
                </div>
              ))}
            </dl>
          </div>
        </div>
      </div>
    </MotionConfig>
  );
}
