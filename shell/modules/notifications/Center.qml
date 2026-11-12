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
import QtQuick.Shapes
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
    // Steps are half the nominal delay and 90ms long: the whole card is in
    // by ~190ms, so it reads instant, but still lands in order. Reduced
    // motion: everything at once.
    function revealAt(ms) {
        if (Theme.reduceMotion) return 1;
        const t = Math.max(0, Math.min(1, (clock - ms * 0.5) / 90));
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
    readonly property int padX: 52                 // room for the shadow (none above: it hangs from the bar)
    readonly property int padY: 6
    readonly property int padBottom: 84
    function cardH(screen) { return Math.round(Math.min(780, Math.max(440, (screen ? screen.height : 1000) * 0.74))); }
    // The card fits what the tab shows (one notification: a short card, not
    // 780 px of nothing), up to cardH. The surface stays cardH tall.
    function fitH(screen) {
        const max = cardH(screen);
        const want = ui && ui.wantH > 0 ? ui.wantH : max;
        return Math.round(Math.min(max, Math.max(300, want)));
    }

    property var shownScreen: Quickshell.screens[0]

    // Where the card is on its screen, now (the scrim's cut-out follows it).
    // The card's surface sits under the bar's reserved strip, at the right.
    readonly property real reservedTop: {
        const m = shownScreen ? Hyprland.monitorFor(shownScreen) : null;
        const r = m && m.lastIpcObject ? m.lastIpcObject.reserved : null;
        return r ? r[1] : 40;
    }
    readonly property var cardRect: {
        const sw = shownScreen ? shownScreen.width : 1920;
        // Always the right edge: the card's window is anchored top-right in
        // every bar style. (Centring it under the island here left the scrim's
        // hole mid-screen, an undimmed slab, while the card itself was dimmed.)
        const ox = sw - (cardW + 12 + padX);
        const oy = reservedTop + Theme.barGap;
        const dh = fitH(shownScreen);
        if (mode === "morph")
            return { x: ox + lerp(from.x, padX, p), y: oy + lerp(from.y, padY, p), w: lerp(from.w, cardW, p), h: lerp(from.h, dh, p), r: lerp(from.r, 22, Math.min(1, p)) };
        return { x: ox + padX, y: oy + padY, w: cardW, h: dh, r: 22 };
    }
    onOpenChanged: {
        if (open) { warm = true; coolDown.stop(); } else { coolDown.restart(); peeking = false; }
        if (open) {
            const reopening = foldAnim.running;
            if (!reopening) shownScreen = (Notifs.centerScreen ? Screens.screenNamed(Notifs.centerScreen) : Screens.focused) || shownScreen;
            if (!reopening) {
                const ft = Notifs.frontToast;
                const pr = Notifs.centerMorphFromRect;
                if (Notifs.centerMorphFrom === "peek" && pr && !Theme.reduceMotion) {
                    mode = "morph";
                    morph.tier = Theme.springSlow;
                    from = {
                        x: padX + (cardW - pr.w) / 2,
                        y: padY + 6,
                        w: pr.w,
                        h: pr.h,
                        r: pr.r
                    };
                    Notifs.centerMorphFrom = "";
                    Notifs.centerMorphFromRect = null;
                } else if (ft && ft.screen === (Notifs.centerScreen || Screens.focusedName) && !Theme.reduceMotion) {
                    mode = "morph";
                    morph.tier = Theme.springSlow;
                    from = { x: padX + cardW + 12 - 16 - Theme.toastWidth, y: 12, w: Theme.toastWidth, h: ft.height, r: 22 };
                } else {
                    mode = "pop";
                    morph.tier = Theme.springModerate;
                    if (Settings.bar === "island" && !Theme.reduceMotion)
                        from = { x: padX + (cardW - 48) / 2, y: padY - 4, w: 48, h: 34, r: 17 };
                }
            }
            capturing = false;
            armed = false;
            if (ui) ui.reset();
            if (ui && Notifs.centerTab === "notifications") Qt.callLater(() => ui.notifications.applyHandoff());
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
            if (ui && !Notifs.centerFocusReply) ui.search.forceActiveFocus();
        } else {
            pendingBegin = false;
            capturing = false;
            armed = false;
            closeT = morph.value;
            clockRun.stop();
            contentOut.restart();
            foldAnim.restart();
        }
    }

    // The card's content is built the first time it opens, on the screen
    // that shows it, and kept a few minutes after it closes (opening again
    // is just motion), then released: ~150 MB that sat unused while closed,
    // a full copy per monitor. The surfaces stay mapped (1×1) as before.
    property bool warm: false
    Timer { id: coolDown; interval: 180000; onTriggered: root.warm = root.open || root.folding }
    Component.onCompleted: console.info("center: ready")
    property bool pendingBegin: false
    function begin() {
        if (!pendingBegin || !open) return;
        console.info("center: begin on " + (shownScreen ? shownScreen.name : "?"));
        pendingBegin = false;
        morph.target = 1;
        clockRun.restart();
        armSoon.restart();
    }
    // Click-outside-closes (the focus grab) is armed only once the card is
    // on screen with the keyboard: armed while the surface was still growing
    // from 1×1, Hyprland cleared it at once and the center shut as it opened.
    property bool armed: false
    Timer { id: armSoon; interval: 120; onTriggered: root.armed = root.open }
    // Fallback if the surface already has its size (reopening) or is slow.
    Timer { id: beginSoon; interval: 34; onTriggered: root.begin() }

    function lerp(a, b, t) { return a + (b - a) * t; }
    // Tooltips on the hosting copy's layer (components/Tips).
    function tip(item, on, text, keys) { if (!ui) return; if (on) ui.tips.show(item, text, keys); else ui.tips.hide(item); }
    function currentView() { return ui ? ui.currentView() : null; }

    // ── Screenshots ──────────────────────────────────────────────────────
    // A click elsewhere closes the center (the focus grab clears). But a
    // screenshot picker (slurp, hyprpicker's freeze, grimblast…) also takes
    // the pointer and keyboard: then the center stays, hands the keyboard
    // over, and takes it back once the picker has gone.
    property bool capturing: false
    // Shown for a screenshot or visual check (centerdebug.peek): no keyboard
    // grab and no focus grab, so whoever is typing keeps typing.
    property bool peeking: false
    readonly property var captureTools: ["pgrep", "-x", "slurp|hyprpicker|grim|grimblast|hyprshot|wayfreeze|satty|swappy|wf-recorder|wl-screenrec|gpu-screen-reco"]
    function grabCleared() {
        console.info("center: focus grab cleared (open=" + open + ", armed=" + armed + ")");
        if (open && armed) captureProbe.running = true;
    }
    Process {
        id: captureProbe
        command: root.captureTools
        onExited: code => {
            console.info("center: screenshot tool running: " + (code === 0));
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
        // Open on a tab without taking the keyboard (for screenshots); unpeek closes.
        function peek(tab: string): void {
            root.peeking = true;
            Notifs.centerTab = ["sound", "controls"].includes(tab) ? tab : "notifications";
            Notifs.setCenter(true, "key");
        }
        function unpeek(): void { Notifs.setCenter(false, "key"); root.peeking = false; }
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
    // Its own surface on the layer under the card's, click-through (the focus
    // grab handles a click out), named outside rice-* so Hyprland doesn't blur
    // under it. Like the card it stays mapped, 1×1 while closed, so opening
    // never waits for a new surface.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: scrim
            required property ShellScreen modelData
            screen: modelData
            readonly property bool up: root.shownScreen === modelData && (root.open || root.folding)
            anchors { top: true; left: true }
            implicitWidth: up ? modelData.width : 1
            implicitHeight: up ? modelData.height : 1
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "rice.scrim"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // A spotlight from the bell: darkest far away, lighter toward the
            // card, and nothing under the card itself (its glass shows the
            // desktop as it is). The light spreads out as the card opens.
            Shape {
                id: spot
                anchors.fill: parent
                visible: scrim.up
                readonly property real t: Math.max(0, Math.min(1, root.p))
                readonly property var c: root.cardRect
                opacity: t
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillRule: ShapePath.OddEvenFill
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: spot.c.x + spot.c.w; centerY: spot.c.y
                        focalX: centerX; focalY: centerY
                        centerRadius: Math.hypot(spot.width, spot.height) * (Theme.reduceMotion ? 1 : 0.75 + 0.25 * spot.t)
                        focalRadius: 0
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.06) }
                        GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.22) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.42) }
                    }
                    PathRectangle { x: 0; y: 0; width: spot.width; height: spot.height }
                    PathRectangle { x: spot.c.x + 1; y: spot.c.y + 1; width: spot.c.w - 2; height: spot.c.h - 2; radius: spot.c.r }
                }
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
            // The hosting monitor's content is the one keys and resets go to.
            function claim() {
                if (!hosts || !body.item) return;
                root.ui = body.item;
                if (root.open) body.item.search.forceActiveFocus();
            }
            onHostsChanged: claim()
            readonly property bool up: hosts && (root.open || root.folding)
            readonly property int fullW: root.cardW + 12 + root.padX
            readonly property int fullH: root.cardH(modelData) + root.padY + root.padBottom

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
            WlrLayershell.keyboardFocus: up && root.open && !root.capturing && !root.peeking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            mask: Region { item: win.up ? frame : null }

            HyprlandFocusGrab {
                windows: [win]
                active: win.up && root.open && root.armed && !root.capturing && !root.peeking
                onCleared: root.grabCleared()
            }

            // Destination: the full card.
            readonly property real dx: root.padX
            readonly property real dy: root.padY
            readonly property real dw: root.cardW
            // Grows and shrinks with the tab (switching tabs, a list getting
            // longer); on open it starts at the right size.
            property real dh: root.fitH(modelData)
            Behavior on dh {
                enabled: root.open && root.p > 0.98 && !Theme.reduceMotion
                NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }

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

                // Elevation from layered shadows, not one big smudge: a tight
                // contact shadow that grounds the edge, a mid one for form,
                // and a wide soft ambient one that lifts the card off the page.
                RectangularShadow {
                    anchors.fill: glass
                    radius: glass.radius
                    offset.y: 30
                    blur: 72
                    spread: -14
                    color: Qt.rgba(0, 0, 0, 0.42 * Math.min(1, root.p))
                }
                RectangularShadow {
                    anchors.fill: glass
                    radius: glass.radius
                    offset.y: 10
                    blur: 24
                    spread: -6
                    color: Qt.rgba(0, 0, 0, 0.30 * Math.min(1, root.p))
                }
                RectangularShadow {
                    anchors.fill: glass
                    radius: glass.radius
                    offset.y: 1
                    blur: 3
                    spread: 0
                    color: Qt.rgba(0, 0, 0, 0.35 * Math.min(1, root.p))
                }
                GlassCard {
                    id: glass
                    anchors.fill: parent
                    radius: frame.radius
                    tint: Theme.glassIsland
                }
                // The island's glass edge, so the center reads as the same material.
                LiquidRim {
                    anchors.fill: glass
                    radius: glass.radius
                    full: 1
                    strength: Math.min(1, root.p) * 0.8
                    light: centerHover.hovered && !Theme.reduceMotion ? centerHover.point.position : Qt.point(width * 0.22, height + 120)
                }
                HoverHandler { id: centerHover }

                Item {
                    anchors.fill: parent
                    clip: true

                    // Built in the background (asynchronously, so nothing
                    // blocks) on the hosting monitor while warm (root.warm).
                    Loader {
                        id: body
                        asynchronous: true
                        active: win.hosts && root.warm
                        // Morph: pinned to the destination and revealed by the
                        // growing clip. Pop: rides along with the card.
                        x: frame.morphing ? win.dx - frame.x : 0
                        y: frame.morphing ? win.dy - frame.y : 0
                        width: win.dw
                        height: win.dh
                        opacity: root.contentFade
                        sourceComponent: CenterContent {
                            center: root
                            hosting: win.hosts
                        }
                        onLoaded: win.claim()
                    }
                }
            }
        }
    }
}
