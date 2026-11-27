import { describe, expect, test } from "bun:test";
import { functions } from "../helpers/qml.mjs";

function harness(themeIcons) {
  const calls = [];
  const scope = {
    Quickshell: { iconPath: (name) => { calls.push(name); return themeIcons[name] || ""; } },
    iconCache: { names: {}, count: 0, misses: {} },
    iconRev: 0,
    restarts: 0,
    iconScan: null,
  };
  scope.iconScan = { restart: () => scope.restarts++ };
  return { s: functions("shell/services/NotifAdapters.qml", ["iconSource", "applyIconResolutions"], scope), calls, scope };
}

describe("iconSource misses", () => {
  test("a theme hit is answered and cached without a scan", () => {
    const { s, scope } = harness({ firefox: "image://icon/firefox" });
    expect(s.iconSource("firefox")).toBe("image://icon/firefox");
    expect(scope.iconCache.names.firefox).toBe("image://icon/firefox");
    expect(scope.iconCache.misses.firefox).toBeUndefined();
    expect(scope.restarts).toBe(0);
  });
  test("a miss is recorded and the scan timer restarted once per name", () => {
    const { s, calls, scope } = harness({});
    expect(s.iconSource("ardia")).toBe("");
    expect(scope.iconCache.misses.ardia).toBe(true);
    expect(scope.restarts).toBe(1);
    s.iconSource("ardia");
    expect(calls.filter(c => c === "ardia").length).toBe(1);
    expect(scope.restarts).toBe(1);
  });
  test("paths and urls never reach the theme lookup", () => {
    const { s, calls } = harness({});
    expect(s.iconSource("/abs/icon.png")).toBe("file:///abs/icon.png");
    expect(s.iconSource("image://qsimage/x")).toBe("image://qsimage/x");
    expect(s.iconSource("https://x/y.png")).toBe("");
    expect(calls.length).toBe(0);
  });
});

describe("applyIconResolutions", () => {
  test("a resolved miss becomes a file url, leaves the misses, and bumps iconRev", () => {
    const { s, scope } = harness({});
    s.iconSource("ardia");
    const rev = scope.iconRev;
    s.applyIconResolutions("ardia\t/usr/share/icons/hicolor/256x256/apps/ardia.png\n");
    expect(scope.iconCache.names.ardia).toBe("file:///usr/share/icons/hicolor/256x256/apps/ardia.png");
    expect(scope.iconCache.misses.ardia).toBeUndefined();
    expect(scope.iconRev).toBe(rev + 1);
    expect(s.iconSource("ardia")).toBe("file:///usr/share/icons/hicolor/256x256/apps/ardia.png");
  });
  test("noise lines apply nothing and iconRev stays", () => {
    const { s, scope } = harness({});
    const rev = scope.iconRev;
    s.applyIconResolutions("\nno-tab-here\n\t\n\tmissing-name\n");
    expect(Object.keys(scope.iconCache.names).length).toBe(0);
    expect(scope.iconRev).toBe(rev);
  });
  test("a name the helper did not find stays a miss for the next scan", () => {
    const { s, scope } = harness({});
    s.iconSource("ghost");
    s.applyIconResolutions("other\t/usr/share/icons/hicolor/48x48/apps/other.png\n");
    expect(scope.iconCache.misses.ghost).toBe(true);
    expect(s.iconSource("ghost")).toBe("");
  });
});

describe("misses cap", () => {
  test("two hundred misses wipe before the next is recorded", () => {
    const { s, scope } = harness({});
    for (let i = 0; i < 200; i++) scope.iconCache.misses["old" + i] = true;
    s.iconSource("fresh");
    expect(Object.keys(scope.iconCache.misses)).toEqual(["fresh"]);
  });
});
