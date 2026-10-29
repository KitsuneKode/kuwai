// The center: Notifications, Agents (kittymux), Sound and Controls on one
// glass card hanging from the bar at the right edge of the focused monitor.
//
// Open: Super+N (Notifications), Super+Shift+N (Agents), the Waybar bell,
// `bin/rice center [tab]`. Esc clears the search, then closes; so does a
// click anywhere else.
//
// It's a menu, not a column: a floating card on lighter glass than the
// windows with a deep shadow, over a scrim that dims everything else. Motion:
// it scales up from its top-right corner (where the bell is) on the moderate
// spring: 0.96 → 1, 6px drop, fading in, then its content 40ms a step
// behind; it closes the same way on a 120ms ease-out. If toasts are on
// screen it instead morphs out of the front one (the slow spring): one glass
// surface whose rectangle and radius grow into the card. Reopening mid-close
// turns it around. Reduced motion: a plain fade.
//
// The surface never goes away. Qt stops laying out (polishing) a window's
// items once that window has been hidden and shown again: rows piled up at
// x=0 and lists stayed empty. So each monitor keeps one card surface for
// good, shrunk to 1×1 and click-through while closed (nothing to blur, no
// input), grown to the card's size to open. That also skips Hyprland's map
// on every open: the card starts a frame later.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    readonly property bool open: Notifs.centerOpen
    readonly property string tab: Notifs.centerTab
    // The hosting monitor's content (CenterContent), once built.
    property Item ui: null

    // ── Search, shared by every tab ──────────────────────────────────────
    property string query: ""
    readonly property var terms: query.toLowerCase().split(/\s+/).filter(t => t)
    function matchesText(text) {
        if (!terms.length) return true;
        const hay = (text || "").toLowerCase();
        return terms.every(t => hay.includes(t));
    }
    // Matches in StyledText: escaped, each term in Apple's yellow.
    function highlight(text) {
        const esc = s => (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        if (!terms.length) return esc(text);
        const pattern = new RegExp("(" + terms.map(t => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|") + ")", "gi");
        return (text || "").split(pattern).map((part, k) => k % 2 ? `<font color="${Theme.yellow}"><b>${esc(part)}</b></font>` : esc(part)).join("");
    }
    // Results update instantly while typing, like Spotlight: choreography
    // between keystrokes only reads as lag.
    property bool instant: false
    onQueryChanged: snap()
    onTabChanged: snap()
    function snap() { instant = true; settle.restart(); }
    Timer { id: settle; interval: 80; onTriggered: root.instant = false }

    // ── Reveal clock: content fades in a step apart after the card ───────
    property real clock: 0
    NumberAnimation { id: clockRun; target: root; property: "clock"; from: 0; to: 600; duration: 600 }
    function revealAt(ms) {
        const t = Math.max(0, Math.min(1, (clock - ms) / 120));
        return 1 - Math.pow(1 - t, 3);      // ease-out
    }

    // ── Open/close ───────────────────────────────────────────────────────
    property string mode: "pop"                    // pop (from the bell's corner) | morph (out of a toast)
    Spring { id: morph; tier: Theme.springSlow; epsilon: 0.0008 }
    property real closeT: 0                        // 1 → 0 on the exit tween
    readonly property real p: open ? morph.value : closeT
    property var from: ({ x: 0, y: 0, w: 44, h: 32, r: 16 })
    property real contentFade: 1
    readonly property bool folding: foldAnim.running

    NumberAnimation {
        id: foldAnim; target: root; property: "closeT"; to: 0
        duration: root.mode === "morph" ? Theme.springSlow.exitMs : Theme.springModerate.exitMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.mode === "morph" ? Theme.easeInOut : Theme.easeOut
        onFinished: morph.snap(0)
    }
    NumberAnimation { id: contentOut; target: root; property: "contentFade"; to: 0; duration: Theme.springFast.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    // Card geometry, shared by every monitor's surface.
    readonly property int cardW: 420
    readonly property int padX: 40                 // room for the shadow (none above: it hangs from the bar)
    readonly property int padY: 6
    function cardH(screen) { return Math.round(Math.min(780, Math.max(440, (screen ? screen.height : 1000) * 0.74))); }

    property var shownScreen: Quickshell.screens[0]
    onOpenChanged: {
        if (open) {
            const reopening = foldAnim.running;
            if (!reopening) shownScreen = Screens.focused || shownScreen;
            const ft = Notifs.frontToast;
            if (!reopening) {
                mode = ft && ft.screen === Screens.focusedName && !Theme.reduceMotion ? "morph" : "pop";
                morph.tier = mode === "morph" ? Theme.springSlow : Theme.springModerate;
                if (mode === "morph")
                    from = { x: padX + cardW + 12 - 16 - Theme.toastWidth, y: 12, w: Theme.toastWidth, h: ft.height, r: 22 };
            }
            capturing = false;
            if (ui) ui.reset();
            foldAnim.stop();
            contentOut.stop();
            contentFade = 1;
            // Reopened while closing: continue from where it is, not from 0.
            morph.snap(reopening ? closeT : 0);
            if (!reopening) clock = 0;
            // The surface grows to the card's size first (one configure from
            // Hyprland); start once it has, or a spring started before that
            // would show up already part way through.
            pendingBegin = true;
            beginSoon.restart();
            if (ui) ui.search.forceActiveFocus();
        } else {
            pendingBegin = false;
            capturing = false;
            closeT = morph.value;
            clockRun.stop();
            contentOut.restart();
            foldAnim.restart();
        }
    }

    property bool pendingBegin: false
    function begin() {
        if (!pendingBegin || !open) return;
        pendingBegin = false;
        morph.target = 1;
        clockRun.restart();
    }
    // Fallback if the surface already has its size (reopening) or is slow.
    Timer { id: beginSoon; interval: 34; onTriggered: root.begin() }

    function lerp(a, b, t) { return a + (b - a) * t; }
    function currentView() { return ui ? ui.currentView() : null; }

    // ── Screenshots ──────────────────────────────────────────────────────
    // A click elsewhere closes the center (the focus grab clears). But a
    // screenshot picker (slurp, hyprpicker's freeze, grimblast…) also takes
    // the pointer and keyboard: then the center stays, hands the keyboard
    // over, and takes it back once the picker has gone.
    property bool capturing: false
    readonly property var captureTools: ["pgrep", "-x", "slurp|hyprpicker|grim|grimblast|hyprshot|wayfreeze|satty|swappy|wf-recorder|wl-screenrec|gpu-screen-reco"]
    function grabCleared() {
        if (open) captureProbe.running = true;
    }
    Process {
        id: captureProbe
        command: root.captureTools
        onExited: code => {
            if (code === 0) root.capturing = true;
            else Notifs.setCenter(false, "pointer");
        }
    }
    Timer {
        interval: 400
        repeat: true
        running: root.capturing && root.open
        onTriggered: if (!captureWatch.running) captureWatch.running = true
    }
    Process {
        id: captureWatch
        command: root.captureTools
        onExited: code => {
            if (code !== 0 && root.capturing) {
                root.capturing = false;
                if (root.ui) root.ui.search.forceActiveFocus();
            }
        }
    }

    // Diagnostics (read-only): where the header and the views sit.
    IpcHandler {
        target: "centerdebug"
        function dump(): string {
            const kids = it => { const o = []; if (!it) return o; for (let k = 0; k < it.children.length; k++) { const c = it.children[k]; o.push([Math.round(c.x), Math.round(c.width), c.visible]); } return o; };
            const tabsRow = root.ui ? root.ui.tabs.children[1] : null;
            return JSON.stringify({
                open: root.open, folding: root.folding, capturing: root.capturing, clock: root.clock, p: root.p,
                screen: root.shownScreen ? root.shownScreen.name : null, ui: !!root.ui,
                tabs: root.ui ? { w: root.ui.tabs.width, implicit: root.ui.tabs.implicitWidth, items: kids(tabsRow) } : null,
                groups: root.ui ? root.ui.notifications.groupCount : null,
                listCount: root.ui ? root.ui.notifications.listCount : null,
                limits: { source: Limits.source, providers: (Limits.providers || []).length, watching: Limits.watching }
            });
        }
    }

    // ── Scrim: everything else steps back while the card is up ────────────
    // Its own surface on the layer under the card's, mapped only while the
    // card is up, and click-through (the focus grab handles a click out).
    // Named outside rice-* so Hyprland doesn't blur under it.
    LazyLoader {
        active: root.open || root.folding
        PanelWindow {
            screen: root.shownScreen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "rice.scrim"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.22 * Math.max(0, Math.min(1, root.p))
            }
        }
    }

    // ── The card: one surface per monitor, for good ───────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            // This monitor hosts the card (and its content).
            readonly property bool hosts: root.shownScreen === modelData
            readonly property bool up: hosts && (root.open || root.folding)
            readonly property int fullW: root.cardW + 12 + root.padX
            readonly property int fullH: root.cardH(modelData) + root.padY + 56

            anchors.top: true
            anchors.right: true
            margins.top: Theme.barGap
            implicitWidth: up ? fullW : 1
            implicitHeight: up ? fullH : 1
            onHeightChanged: if (up && height >= fullH) Qt.callLater(root.begin)
            exclusionMode: ExclusionMode.Normal
            color: "transparent"

            WlrLayershell.namespace: "rice-center"
            WlrLayershell.layer: WlrLayer.Overlay
            // Keyboard goes to the center while it's open: it was opened on
            // purpose, and Esc or any click elsewhere hands it straight back.
            WlrLayershell.keyboardFocus: up && root.open && !root.capturing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            mask: Region { item: win.up ? frame : null }

            HyprlandFocusGrab {
                windows: [win]
                active: win.up && root.open && !root.capturing
                onCleared: root.grabCleared()
            }

            // Destination: the full card.
            readonly property real dx: root.padX
            readonly property real dy: root.padY
            readonly property real dw: root.cardW
            readonly property real dh: root.cardH(modelData)

            // The morphing surface: rectangle and radius between source and
            // destination; content stays put inside and is revealed by the clip.
            Item {
                id: frame
                visible: win.up
                readonly property bool morphing: root.mode === "morph"
                // pop: the card itself, scaling up from its top-right corner
                // morph: a rectangle growing from the front toast into the card
                x: morphing ? root.lerp(root.from.x, win.dx, root.p) : win.dx
                y: morphing ? root.lerp(root.from.y, win.dy, root.p)
                            : win.dy - (Theme.reduceMotion ? 0 : (1 - Math.min(1, root.p)) * 6)
                width: morphing ? Math.max(1, root.lerp(root.from.w, win.dw, root.p)) : win.dw
                height: morphing ? Math.max(1, root.lerp(root.from.h, win.dh, root.p)) : win.dh
                readonly property real radius: morphing ? root.lerp(root.from.r, 22, Math.min(1, root.p)) : 22
                transformOrigin: Item.TopRight
                scale: morphing || Theme.reduceMotion ? 1 : 0.96 + 0.04 * root.p
                opacity: morphing ? Math.min(1, root.p * 5) : Math.min(1, root.p * 1.6)

                RectangularShadow {
                    anchors.fill: glass
                    radius: glass.radius
                    offset.y: 18
                    blur: 48
                    spread: -6
                    color: Qt.rgba(0, 0, 0, 0.5 * Math.min(1, root.p))
                }
                GlassCard {
                    id: glass
                    anchors.fill: parent
                    radius: frame.radius
                    tint: Theme.glassTintElevated
                }

                Item {
                    anchors.fill: parent
                    clip: true

                    // Built once this monitor first hosts the card, kept
                    // while it does: opening is then just motion.
                    Loader {
                        active: win.hosts
                        // Morph: pinned to the destination and revealed by the
                        // growing clip. Pop: rides along with the card.
                        x: frame.morphing ? win.dx - frame.x : 0
                        y: frame.morphing ? win.dy - frame.y : 0
                        width: win.dw
                        height: win.dh
                        opacity: root.contentFade
                        sourceComponent: CenterContent {
                            id: cc
                            center: root
                            Component.onCompleted: {
                                root.ui = cc;
                                if (root.open) cc.search.forceActiveFocus();
                            }
                            Component.onDestruction: if (root.ui === cc) root.ui = null
                        }
                    }
                }
            }
        }
    }
}
