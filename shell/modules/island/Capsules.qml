// Workspace pills, as in the reference: slim capsules side by side; the one
// you're on stands taller, wider and lit in the theme's colour with a soft
// glow; occupied ones are a quiet tint of it, empty ones darker still. Hover
// a pill for its number and what's open there.
// The height rides a spring with a little give, so moving between
// workspaces reads as one pill rising while the other settles.
//
// Each island speaks for its own screen: a click or a scroll acts on that
// screen. The focused screen's pills are fully lit; the others are quieter,
// so you can see where your keys will act.
//
// After them, one small dim pill for the workspace the other screen is
// showing. Hover for which; click to go there (your focus goes with it).
//
// The special (hidden, scratchpad) workspace shows as an extra ring that
// pops in on a bouncier spring while it's open, and the others dim behind
// it: it sits on top of your workspace, not beside it.
//
// Click to go there; scroll to step through (a wheel notch is one step, a
// touchpad swipe is one step). Hovering here never expands the island
// (`hovered`), so the pills stay clickable.
// `bar` is the island bar window (screenName, activeWs, wsList, mine, special, focusedHere, others).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.services

Row {
    id: caps
    required property var bar
    property real scale: 1
    readonly property bool hovered: hover.hovered
    spacing: px(5 * scale)
    height: 20 * scale
    // Whole device pixels (the laptop runs at 1.33×: a 7 px pill there is
    // 9.33 real pixels, and its edges smear).
    readonly property real dpr: Screen.devicePixelRatio || 1
    function px(v) { return Math.round(v * dpr) / dpr; }
    // What's open on a workspace, for the tooltips: "Firefox, Kitty +2".
    function apps(id) {
        const names = [];
        for (const t of Hyprland.toplevels.values) {
            if (!t.workspace || t.workspace.id !== id) continue;
            const cls = (t.lastIpcObject && t.lastIpcObject.class) || (t.wayland ? t.wayland.appId : "") || "";
            const e = cls ? DesktopEntries.heuristicLookup(cls) : null;
            const n = e && e.name ? e.name : cls ? cls.charAt(0).toUpperCase() + cls.slice(1) : "";
            if (n && names.indexOf(n) < 0) names.push(n);
        }
        if (!names.length) return "empty";
        return names.slice(0, 3).join(", ") + (names.length > 3 ? " +" + (names.length - 3) : "");
    }
    function num(id) { return ((id - 1) % 10) + 1; }
    // The apps open on a workspace, for the island's hint: [{ name, icon }].
    function entries(id) {
        const out = [], seen = {};
        for (const t of Hyprland.toplevels.values) {
            if (!t.workspace || t.workspace.id !== id) continue;
            const cls = (t.lastIpcObject && t.lastIpcObject.class) || (t.wayland ? t.wayland.appId : "") || "";
            if (!cls || seen[cls]) continue;
            seen[cls] = true;
            const e = DesktopEntries.heuristicLookup(cls);
            out.push({ name: e && e.name ? e.name : cls, icon: e && e.icon ? e.icon : cls.toLowerCase() });
        }
        return out;
    }
    // The pill under the pointer, for the island to name in place of the
    // clock (IslandRest): { id, screen: "" here, or "Laptop"/"Acer" }.
    // Where nothing shows it (the expanded view), a tooltip does.
    property var hint: null
    property bool tips: true
    function hover(id, screen, on) {
        if (on) hint = { id: id, screen: screen || "" };
        else if (hint && hint.id === id) hint = null;
    }

    // Near counts as on: the pointer heading for a pill shouldn't grow the
    // island under it (IslandBar.overPills), so the zone reaches past the row.
    HoverHandler { id: hover; margin: 10 * caps.scale }
    // The same stepping as Super+Ctrl+← →, on this island's screen. A wheel
    // notch (120) is one step; a touchpad swipe sends many small deltas, so
    // it steps once per swipe (a pause of 250 ms ends the swipe).
    property real wheelAcc: 0
    property bool swiped: false
    function step(d) { Hyprland.dispatch("kuwai.ws_step(" + d + ", " + JSON.stringify(caps.bar.screenName) + ")"); }
    Timer { id: swipeEnd; interval: 250; onTriggered: { caps.wheelAcc = 0; caps.swiped = false; } }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            swipeEnd.restart();
            caps.wheelAcc += event.angleDelta.y;
            const touchpad = event.pixelDelta.y !== 0;
            if (touchpad) {
                if (!caps.swiped && Math.abs(caps.wheelAcc) >= 60) { caps.swiped = true; caps.step(caps.wheelAcc > 0 ? -1 : 1); }
                return;
            }
            while (Math.abs(caps.wheelAcc) >= 120) {
                const d = caps.wheelAcc > 0 ? -1 : 1;
                caps.wheelAcc += d * 120;
                caps.step(d);
            }
        }
    }

    Repeater {
        model: caps.bar.wsList
        Item {
            id: cap
            required property int index
            required property var modelData
            readonly property int ws: modelData.id
            readonly property bool guest: modelData.guest
            // Its number on its own screen (kuwai: 1–10 per screen).
            readonly property int label: caps.num(ws)
            readonly property var wsObj: caps.bar.mine.find(w => w.id === ws) || null
            readonly property int windows: modelData.windows !== undefined ? modelData.windows : (wsObj && wsObj.toplevels ? wsObj.toplevels.values.length : 0)
            readonly property bool on: ws === caps.bar.activeWs
            readonly property bool used: modelData.used !== undefined ? modelData.used : caps.bar.mine.some(w => w.id === ws && w.toplevels && w.toplevels.values.length > 0)
            // The first guest (another screen's workspace) keeps a little distance.
            readonly property bool firstGuest: guest && (index === 0 || !caps.bar.wsList[index - 1].guest)
            // Sizes from the reference: short stubs, the current one a tall
            // capsule; snapped to whole device pixels so edges stay crisp at
            // fractional scales.
            width: caps.px(pill.width + (firstGuest ? 6 * caps.scale : 0))
            height: caps.height
            opacity: caps.bar.special ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

            Spring { id: grow; tier: ({ stiffness: 520, damping: 38 }); target: cap.on ? 1 : 0; Component.onCompleted: settle() }   // settles with the workspace slide (kuwaiPage 520), a hint of give
            readonly property real g: Math.max(0, Math.min(1.1, grow.value))
            // Lit = full accent and a glow on the focused screen; on the other
            // screen the current one keeps its size but is lit at half.
            property real lit: caps.bar.focusedHere ? 1 : 0.42
            Behavior on lit { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            readonly property real rest: cap.used ? (capArea.containsMouse ? 0.45 : 0.3) : (capArea.containsMouse ? 0.3 : 0.16)
            RectangularShadow {
                anchors.fill: pill
                radius: pill.radius
                blur: 9
                spread: 0
                color: Qt.alpha(Theme.accent, 0.6 * Math.max(0, Math.min(1, cap.g)) * Math.max(0, (cap.lit - 0.42) / 0.58))
                visible: color.a > 0.01
            }
            Rectangle {
                id: pill
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                width: caps.px((7 + 2 * Math.min(1, cap.g)) * caps.scale)
                height: caps.px((12 + 6 * cap.g) * caps.scale)
                radius: width / 2
                color: cap.guest && !cap.on ? "transparent"
                     : Qt.alpha(Theme.accent, cap.rest + (cap.lit - cap.rest) * Math.max(0, Math.min(1, cap.g)))
                // Guests (from a screen that's gone): hollow, so they read as visiting.
                border.width: cap.guest && !cap.on ? 1.5 : 0
                border.color: Qt.alpha(Theme.accent, capArea.containsMouse ? 0.8 : 0.5)
            }
            MouseArea {
                id: capArea
                // Hit area: the whole column, gaps included (half to each
                // neighbour), and the island's height: no dead spots between
                // pills, nothing to aim for. Only the pill itself is drawn.
                anchors.fill: parent
                anchors.leftMargin: -caps.spacing / 2 - (cap.index === 0 ? 6 * caps.scale : 0)
                anchors.rightMargin: -caps.spacing / 2
                anchors.topMargin: -8 * caps.scale
                anchors.bottomMargin: -8 * caps.scale
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: caps.hover(cap.ws, "", containsMouse)
                // On this island's screen; the lit one does nothing (no bounce).
                // Desktops: every screen switches together (kuwai.desktop).
                onClicked: Hyprland.dispatch(cap.modelData.desktop ? "kuwai.desktop(" + cap.modelData.desktop + ")" : "kuwai.show_ws(" + JSON.stringify(caps.bar.screenName) + ", " + cap.ws + ")")
            }
            Tip {
                text: (cap.modelData.desktop ? "Desktop " : "Workspace ") + cap.label + (cap.guest ? " (from another screen)" : "") + " · " + caps.apps(cap.ws)
                shown: caps.tips && capArea.containsMouse
                below: true
            }
        }
    }

    Repeater {
        // Only what the other screen is showing (all of its workspaces too
        // was a second row to read): one dim pill, on the right.
        model: caps.bar.others.map(o => Object.assign({}, o, { list: o.list.filter(w => w.on) })).filter(o => o.list.length)
        Dots { required property var modelData; group: modelData; divider: "left" }
    }

    // A special workspace (scratchpad, notes, console, minimized) open on this
    // screen: an accent capsule with its glyph pops in on a bouncy spring, and
    // the workspace pills dim behind it — it sits on top of your workspace.
    Item {
        id: sp
        readonly property string name: (caps.bar.special || "").replace(/^special:/, "")
        property string shown: ""
        onNameChanged: if (name) shown = name
        readonly property var glyphs: ({ special: "\u{f0328}", notes: "\u{f082e}", console: "\u{f018d}", minimized: "\u{f05b0}" })
        visible: special.value > 0.01
        width: 24 * caps.scale * Math.min(1, special.value)
        height: caps.height
        Spring { id: special; tier: ({ stiffness: 380, damping: 16 }); target: caps.bar.special ? 1 : 0 }
        RectangularShadow {
            anchors.fill: chip
            radius: chip.radius
            blur: 10; spread: 1
            color: Qt.alpha(Theme.accent, 0.45 * Math.max(0, Math.min(1, special.value)))
        }
        Rectangle {
            id: chip
            anchors.centerIn: parent
            width: 22 * caps.scale; height: 16 * caps.scale
            radius: height / 2
            scale: Math.max(0, special.value)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Qt.lighter(Theme.accent, 1.35) }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.25)
            Text {
                anchors.centerIn: parent
                text: sp.glyphs[sp.shown] || sp.glyphs.special
                font.family: Theme.fontGlyph
                font.pixelSize: 11 * caps.scale
                color: Qt.rgba(0, 0, 0, 0.75)
            }
        }
        MouseArea {
            id: spArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + (sp.shown || "special").replace(/[^A-Za-z0-9_-]/g, "") + "')")
        }
        Tip {
            text: ({ special: "Scratchpad", notes: "Notes", console: "Console", minimized: "Minimized windows" })[sp.shown] || ("Special: " + sp.shown)
            shown: spArea.containsMouse
            below: true
        }
    }

    // Another screen's pills: smaller stubs after a gap, the one it shows
    // lit at half (like the current pill on a screen you're not on), the
    // ones with windows a faint tint.
    component Dots: Row {
        // The other screen's current workspace: in the same rhythm as the
        // pills (no extra gap), a touch larger than an idle one, lit at half
        // with a softer glow than this screen's lit pill: "current, elsewhere".
        id: dots
        property var group
        property string divider: "left"
        spacing: caps.spacing
        height: caps.height
        Repeater {
            model: dots.group ? dots.group.list : []
            Item {
                id: dot
                required property var modelData
                width: caps.px(8 * caps.scale)
                height: caps.height
                RectangularShadow {
                    anchors.fill: dotPill
                    radius: dotPill.radius
                    blur: 6; spread: 0
                    color: Qt.alpha(Theme.accent, dotArea.containsMouse ? 0.4 : 0.22)
                }
                Rectangle {
                    id: dotPill
                    anchors.centerIn: parent
                    width: parent.width
                    height: caps.px(14 * caps.scale)
                    radius: width / 2
                    color: Qt.alpha(Theme.accent, dotArea.containsMouse ? 0.7 : 0.48)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                }
                MouseArea {
                    id: dotArea
                    anchors.fill: parent
                    anchors.leftMargin: -caps.spacing / 2
                    anchors.rightMargin: -caps.spacing / 2 - 6 * caps.scale
                    anchors.topMargin: -8 * caps.scale
                    anchors.bottomMargin: -8 * caps.scale
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: caps.hover(dot.modelData.id, dots.group.label, containsMouse)
                    onClicked: Hyprland.dispatch("kuwai.go_ws(" + JSON.stringify(dots.group.screen) + ", " + dot.modelData.id + ")")
                }
                Tip {
                    text: dots.group.label + " · workspace " + caps.num(dot.modelData.id) + " (showing) · " + caps.apps(dot.modelData.id)
                    shown: caps.tips && dotArea.containsMouse
                    below: true
                }
            }
        }
    }
}
