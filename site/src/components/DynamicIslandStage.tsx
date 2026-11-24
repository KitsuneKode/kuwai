import { useEffect, useRef, useState } from "react";
import { AnimatePresence, MotionConfig, motion } from "motion/react";

type IslandState = "ask" | "rest" | "limits" | "update" | "media" | "wallpaper";

const WALLPAPERS = [
  { src: "/assets/imageory/horizon-arc.webp", name: "Horizon Arc" },
  { src: "/assets/imageory/liquid-silk.webp", name: "Liquid Silk" },
  { src: "/assets/imageory/monolith-portal.webp", name: "Monolith Portal" },
  { src: "/assets/imageory/night-ridge.webp", name: "Night Ridge" },
  { src: "/assets/imageory/architectural-dune.webp", name: "Architectural Dune" }
];

const TABS: { id: IslandState; label: string }[] = [
  { id: "ask", label: "Agent asking" },
  { id: "rest", label: "At rest" },
  { id: "limits", label: "Limits" },
  { id: "update", label: "Updates" },
  { id: "media", label: "Now playing" },
  { id: "wallpaper", label: "Wallpaper" }
];

const GROW_SPRING = { type: "spring" as const, stiffness: 300, damping: 27.7 };
const FOLD_SPRING = { type: "spring" as const, stiffness: 380, damping: 39 };
const FAST_SPRING = { type: "spring" as const, stiffness: 520, damping: 38 };

export default function DynamicIslandStage() {
  const [state, setState] = useState<IslandState>("ask");
  const [expanded, setExpanded] = useState(false);
  const [askStatus, setAskStatus] = useState<"pending" | "allowed" | "denied">("pending");
  const [wallIdx, setWallIdx] = useState(0);
  const [nextWallSrc, setNextWallSrc] = useState<string | null>(null);
  const [revealing, setRevealing] = useState(false);
  const [touring, setTouring] = useState(false);
  const stageRef = useRef<HTMLDivElement>(null);
  const specularRef = useRef<HTMLDivElement>(null);
  const tourTimers = useRef<number[]>([]);

  const clearTour = () => {
    tourTimers.current.forEach((id) => window.clearTimeout(id));
    tourTimers.current = [];
    setTouring(false);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setExpanded(false);
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      tourTimers.current.forEach((id) => window.clearTimeout(id));
    };
  }, []);

  const triggerWallpaper = () => {
    const next = (wallIdx + 1) % WALLPAPERS.length;
    setNextWallSrc(WALLPAPERS[next].src);
    setRevealing(false);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => setRevealing(true));
    });
    window.setTimeout(() => {
      setWallIdx(next);
      setRevealing(false);
      setNextWallSrc(null);
    }, 900);
  };

  const selectState = (next: IslandState, fromUser = true) => {
    if (fromUser && touring) clearTour();
    setState(next);
    if (next === "rest") {
      setExpanded(false);
    } else if (next === "wallpaper") {
      setExpanded(false);
      triggerWallpaper();
    } else {
      setExpanded(true);
    }
  };

  const startTour = () => {
    if (touring) {
      clearTour();
      return;
    }
    setTouring(true);
    setAskStatus("pending");
    setState("rest");
    setExpanded(false);

    const schedule = (ms: number, fn: () => void) => {
      tourTimers.current.push(window.setTimeout(fn, ms));
    };

    schedule(900, () => {
      setState("ask");
      setExpanded(false);
    });
    schedule(2100, () => {
      setExpanded(true);
    });
    schedule(3800, () => {
      setAskStatus("allowed");
    });
    schedule(5200, () => {
      setState("limits");
      setExpanded(true);
    });
    schedule(7100, () => {
      setState("update");
      setExpanded(true);
    });
    schedule(8900, () => {
      setState("media");
      setExpanded(true);
    });
    schedule(10600, () => {
      setState("wallpaper");
      setExpanded(false);
      triggerWallpaper();
    });
    schedule(12200, () => {
      setAskStatus("pending");
      setState("ask");
      setExpanded(false);
      setTouring(false);
    });
  };

  const showAsk = state !== "rest" && state !== "media" && state !== "wallpaper";
  const showWork = state !== "rest" && state !== "update" && state !== "wallpaper";
  const showLimits = state !== "rest" && state !== "media" && state !== "wallpaper";

  const captionMap: Record<IslandState, [string, string]> = {
    ask: [
      "Dedicated approval capsule",
      "Waiting prompts get an orange halo beside the notch while active agents stay quiet."
    ],
    rest: [
      "Calm at rest",
      "Only the clock and a single neutral indicator stay visible until something needs you."
    ],
    limits: [
      "Clear quota countdowns",
      "Leads with whichever provider resets soonest across all signed-in accounts."
    ],
    update: [
      "Reviewed system updates",
      "Official packages upgrade together; community packages show their diff before building."
    ],
    media: [
      "Human-readable media",
      "Cleans messy browser tab titles and shows a local window frame when cover art is missing."
    ],
    wallpaper: [
      "Notch-origin wallpaper reveal",
      `Swapped smoothly from the notch edge to ${WALLPAPERS[wallIdx].name} via imageory.in.`
    ]
  };

  const [capTitle, capDetail] = captionMap[state];

  const onPointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!stageRef.current || !specularRef.current) return;
    const rect = stageRef.current.getBoundingClientRect();
    specularRef.current.style.setProperty("--mx", `${e.clientX - rect.left}px`);
    specularRef.current.style.setProperty("--my", `${e.clientY - rect.top}px`);
  };

  return (
    <MotionConfig reducedMotion="user">
      <div className="stage-shell">
        <div
          ref={stageRef}
          className="desktop-stage"
          onPointerMove={onPointerMove}
          data-state={state}
          data-expanded={expanded ? "true" : "false"}
        >
          <img
            src={WALLPAPERS[wallIdx].src}
            alt="Atmospheric desktop wallpaper from imageory.in"
            className="stage-wallpaper"
          />
          {nextWallSrc && (
            <img
              src={nextWallSrc}
              alt=""
              aria-hidden="true"
              className={`stage-wallpaper stage-wallpaper-next${revealing ? " is-revealing" : ""}`}
            />
          )}
          <div className="stage-scrim" aria-hidden="true" />
          <div ref={specularRef} className="stage-specular" aria-hidden="true" />

          <div className="island-mount">
            <div className="island-cluster">
              <AnimatePresence initial={false}>
                {showAsk && (
                  <motion.button
                    key="ask-capsule"
                    type="button"
                    layout
                    initial={{ opacity: 0, scale: 0.86, y: -4 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    exit={{ opacity: 0, scale: 0.86, y: -4 }}
                    transition={FAST_SPRING}
                    className={`capsule capsule-ask${askStatus !== "pending" ? " is-resolved" : ""}`}
                    onClick={() => selectState("ask")}
                    aria-label="Inspect waiting agent approval"
                  >
                    <span className="agent-mark mark-claude" aria-hidden="true">
                      <svg viewBox="0 0 16 16" width="14" height="14" fill="none">
                        <path d="M8 1.5v13M2.4 4.75l11.2 6.5M13.6 4.75l-11.2 6.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
                      </svg>
                    </span>
                    <span className={`capsule-text ${askStatus === "pending" ? "capsule-text-orange" : "capsule-text-green"}`}>
                      {askStatus === "pending" ? "Approval" : askStatus === "allowed" ? "Approved" : "Blocked"}
                    </span>
                  </motion.button>
                )}

                {showWork && (
                  <motion.button
                    key="work-capsule"
                    type="button"
                    layout
                    initial={{ opacity: 0, scale: 0.86, y: -4 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    exit={{ opacity: 0, scale: 0.86, y: -4 }}
                    transition={FAST_SPRING}
                    className="capsule capsule-work"
                    onClick={() => selectState("ask")}
                    aria-label="View three active agents"
                  >
                    <span className="agent-mark mark-codex" aria-hidden="true">
                      <svg viewBox="0 0 16 16" width="14" height="14" fill="none">
                        <circle cx="8" cy="8" r="5.2" stroke="currentColor" strokeWidth="1.5" />
                        <circle cx="8" cy="8" r="1.8" fill="currentColor" />
                      </svg>
                    </span>
                    <span className="capsule-count tabular">3</span>
                  </motion.button>
                )}
              </AnimatePresence>

              <div className="notch-unit">
                <svg className="notch-ear notch-ear-left" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
                  <path d="M0 0H16V16C16 7.163 8.837 0 0 0Z" fill="currentColor" />
                </svg>

                <motion.div
                  className="notch-body"
                  role="button"
                  tabIndex={0}
                  aria-expanded={expanded}
                  aria-label="Toggle kuwai island panel"
                  animate={{
                    width: expanded ? "min(440px, 84vw)" : 126,
                    minHeight: expanded ? 176 : 38,
                    borderBottomLeftRadius: expanded ? 26 : 18,
                    borderBottomRightRadius: expanded ? 26 : 18,
                    paddingTop: expanded ? 12 : 0,
                    paddingBottom: expanded ? 18 : 0,
                    paddingLeft: 18,
                    paddingRight: 18
                  }}
                  transition={expanded ? GROW_SPRING : FOLD_SPRING}
                  onClick={(e) => {
                    if ((e.target as HTMLElement).closest("button")) return;
                    if (state === "rest" || state === "wallpaper") {
                      selectState("ask");
                      return;
                    }
                    setExpanded((prev) => !prev);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      setExpanded((prev) => !prev);
                    }
                  }}
                >
                  <div className="notch-compact">
                    <span className="notch-clock tabular">22:58</span>
                    <span
                      className={`notch-dot${
                        state === "limits" || (state === "ask" && askStatus === "pending")
                          ? " is-orange"
                          : state === "ask" && askStatus !== "pending"
                            ? " is-green"
                            : ""
                      }`}
                      aria-hidden="true"
                    />
                  </div>

                  <AnimatePresence mode="wait">
                    {expanded && state === "ask" && (
                      <motion.div
                        key={`ask-${askStatus}`}
                        className="notch-panel"
                        initial={{ opacity: 0, y: -5, filter: "blur(3px)" }}
                        animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                        exit={{ opacity: 0, y: -3, filter: "blur(2px)" }}
                        transition={{ duration: 0.18 }}
                      >
                        {askStatus === "pending" ? (
                          <>
                            <div className="np-row">
                              <span className="np-title">Claude Code asks for approval</span>
                              <span className="np-sub">Pane 2</span>
                            </div>
                            <pre className="np-code"><code>bun test tests/shell/agents.test.mjs</code></pre>
                            <div className="np-actions">
                              <button type="button" className="btn-secondary btn-compact" onClick={() => setAskStatus("denied")}>
                                Deny
                              </button>
                              <button type="button" className="btn-primary btn-compact" onClick={() => setAskStatus("allowed")}>
                                Allow
                              </button>
                            </div>
                          </>
                        ) : (
                          <>
                            <div className="np-row">
                              <span className="np-title">
                                {askStatus === "allowed" ? "Claude Code resumed" : "Command blocked"}
                              </span>
                              <span className="np-sub">Native hook</span>
                            </div>
                            <p className="np-sub" style={{ margin: 0 }}>
                              {askStatus === "allowed"
                                ? "Decision delivered directly to the agent without stealing window focus."
                                : "Denied safely before execution. Your active window stayed focused."}
                            </p>
                            <div className="np-actions">
                              <button type="button" className="btn-quiet btn-compact" onClick={() => setAskStatus("pending")}>
                                Replay prompt
                              </button>
                            </div>
                          </>
                        )}
                      </motion.div>
                    )}

                    {expanded && state === "limits" && (
                      <motion.div
                        key="limits"
                        className="notch-panel"
                        initial={{ opacity: 0, y: -5, filter: "blur(3px)" }}
                        animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                        exit={{ opacity: 0, y: -3, filter: "blur(2px)" }}
                        transition={{ duration: 0.18 }}
                      >
                        <div className="np-row">
                          <span className="np-title">AI quota headroom</span>
                          <span className="np-sub tabular">Codex resets in 1h</span>
                        </div>
                        <div className="np-row">
                          <span className="np-sub">Codex (2 accounts)</span>
                          <span className="np-sub tabular">96% used</span>
                        </div>
                        <div className="np-meter-track">
                          <motion.div className="np-meter-fill is-orange" initial={{ width: 0 }} animate={{ width: "96%" }} transition={{ duration: 0.45 }} />
                        </div>
                        <div className="np-row">
                          <span className="np-sub">Devin (2 profiles)</span>
                          <span className="np-sub tabular">41% used</span>
                        </div>
                        <div className="np-meter-track">
                          <motion.div className="np-meter-fill is-green" initial={{ width: 0 }} animate={{ width: "41%" }} transition={{ duration: 0.45 }} />
                        </div>
                      </motion.div>
                    )}

                    {expanded && state === "update" && (
                      <motion.div
                        key="update"
                        className="notch-panel"
                        initial={{ opacity: 0, y: -5, filter: "blur(3px)" }}
                        animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                        exit={{ opacity: 0, y: -3, filter: "blur(2px)" }}
                        transition={{ duration: 0.18 }}
                      >
                        <div className="np-row">
                          <span className="np-title">3 updates ready</span>
                          <span className="np-sub tabular">1 build diff to review</span>
                        </div>
                        <div className="np-row">
                          <span className="np-sub">linux 6.18.2 to 6.18.3</span>
                          <span className="np-sub">Official</span>
                        </div>
                        <div className="np-row">
                          <span className="np-sub">paru-bin 2.1.0 to 2.1.1</span>
                          <span className="np-sub">Verified AUR</span>
                        </div>
                        <div className="np-meter-track">
                          <motion.div className="np-meter-fill" initial={{ width: "18%" }} animate={{ width: "74%" }} transition={{ duration: 0.6 }} />
                        </div>
                      </motion.div>
                    )}

                    {expanded && state === "media" && (
                      <motion.div
                        key="media"
                        className="notch-panel"
                        initial={{ opacity: 0, y: -5, filter: "blur(3px)" }}
                        animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
                        exit={{ opacity: 0, y: -3, filter: "blur(2px)" }}
                        transition={{ duration: 0.18 }}
                      >
                        <div className="np-row">
                          <div>
                            <div className="np-title">Dune: Part Two</div>
                            <div className="np-sub">JioHotstar · live window frame</div>
                          </div>
                          <div className="np-wave" aria-hidden="true">
                            <span />
                            <span />
                            <span />
                            <span />
                          </div>
                        </div>
                        <div className="np-meter-track">
                          <motion.div className="np-meter-fill" initial={{ width: "32%" }} animate={{ width: "58%" }} transition={{ duration: 0.5 }} />
                        </div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </motion.div>

                <svg className="notch-ear notch-ear-right" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
                  <path d="M16 0H0V16C0 7.163 7.163 0 16 0Z" fill="currentColor" />
                </svg>
              </div>

              <AnimatePresence initial={false}>
                {showLimits && (
                  <motion.button
                    key="limits-capsule"
                    type="button"
                    layout
                    initial={{ opacity: 0, scale: 0.86, y: -4 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    exit={{ opacity: 0, scale: 0.86, y: -4 }}
                    transition={FAST_SPRING}
                    className="capsule capsule-limits"
                    onClick={() => selectState("limits")}
                    aria-label="Inspect AI quota limits"
                  >
                    <span className="limit-ring" aria-hidden="true">
                      <svg viewBox="0 0 18 18" width="16" height="16">
                        <circle cx="9" cy="9" r="6.5" fill="none" stroke="rgba(255,255,255,0.16)" strokeWidth="1.8" />
                        <circle cx="9" cy="9" r="6.5" fill="none" stroke="#ff9f0a" strokeWidth="1.8" strokeDasharray="40.8" strokeDashoffset="14" strokeLinecap="round" transform="rotate(-90 9 9)" />
                      </svg>
                    </span>
                    <span className="capsule-text capsule-text-orange tabular">1h</span>
                    <span className="capsule-hairline" aria-hidden="true" />
                    <span className="agent-mark mark-dim" aria-hidden="true">
                      <svg viewBox="0 0 16 16" width="13" height="13" fill="none">
                        <path d="M8 1.5v13M2.4 4.75l11.2 6.5M13.6 4.75l-11.2 6.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                      </svg>
                    </span>
                  </motion.button>
                )}
              </AnimatePresence>
            </div>
          </div>

          <div className="stage-caption">
            <span className="stage-caption-title">{capTitle}</span>
            <span className="stage-caption-detail">{capDetail}</span>
          </div>
        </div>

        <div className="stage-toolbar">
          <div className="segmented" role="tablist" aria-label="Interactive island states">
            {TABS.map((tab) => {
              const active = state === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  role="tab"
                  className="segment-tab"
                  aria-selected={active}
                  onClick={() => selectState(tab.id)}
                >
                  {active && (
                    <motion.span
                      layoutId="stage-tab-pill"
                      className="segment-pill"
                      transition={FAST_SPRING}
                    />
                  )}
                  {tab.label}
                </button>
              );
            })}
          </div>
          <button
            type="button"
            className="btn-quiet btn-compact"
            id="tourToggleBtn"
            onClick={startTour}
          >
            {touring ? "Stop tour" : "Play tour"}
          </button>
        </div>
      </div>
    </MotionConfig>
  );
}
