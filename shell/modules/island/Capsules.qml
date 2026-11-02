// Workspace pills, as in the reference: slim capsules side by side; the one
// you're on stands taller and lit in the theme's colour with a soft glow,
// occupied ones are a quiet tint of it, empty ones darker still. No numbers
// in the bar: hover a pill for its name and windows; Super+Tab shows all.
// The height rides a spring with a little give, so moving between
// workspaces reads as one pill rising while the other settles.
//
// The special (hidden, scratchpad) workspace shows as an extra ring that
// pops in on a bouncier spring while it's open, and the others dim behind
// it: it sits on top of your workspace, not beside it.
//
// Click to go there; scroll to step through. Hovering here never expands
// the island (`hovered`), so the pills stay clickable.
// `bar` is the island bar window (activeWs, wsCount, mine, special).
import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.config
import qs.components

Row {
    id: caps
    required property var bar
    property real scale: 1
    readonly property bool hovered: hover.hovered
    spacing: 4 * scale
    height: 20 * scale

    HoverHandler { id: hover }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        // The same stepping as Super+Alt+← →: this screen's workspaces in order.
        onWheel: event => Hyprland.dispatch("kuwai.ws_step(" + (event.angleDelta.y > 0 ? -1 : 1) + ")")
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
            readonly property int label: ((ws - 1) % 10) + 1
            readonly property var wsObj: caps.bar.mine.find(w => w.id === ws) || null
            readonly property int windows: modelData.windows !== undefined ? modelData.windows : (wsObj && wsObj.toplevels ? wsObj.toplevels.values.length : 0)
            readonly property bool on: ws === caps.bar.activeWs
            readonly property bool used: modelData.used !== undefined ? modelData.used : caps.bar.mine.some(w => w.id === ws && w.toplevels && w.toplevels.values.length > 0)
            // The first guest (another screen's workspace) keeps a little distance.
            readonly property bool firstGuest: guest && (index === 0 || !caps.bar.wsList[index - 1].guest)
            width: (8 + (firstGuest ? 8 : 0)) * caps.scale
            height: caps.height
            opacity: caps.bar.special ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

            Spring { id: grow; tier: ({ stiffness: 520, damping: 38 }); target: cap.on ? 1 : 0; Component.onCompleted: settle() }   // settles with the workspace slide (kuwaiPage 520), a hint of give
            readonly property real g: Math.max(0, Math.min(1.15, grow.value))
            RectangularShadow {
                anchors.fill: pill
                radius: pill.radius
                blur: 10
                spread: 1
                color: Qt.alpha(Theme.accent, 0.55 * Math.max(0, Math.min(1, grow.value)))
                visible: grow.value > 0.02
            }
            Rectangle {
                id: pill
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 1 * caps.scale
                // Slim; the current one a little wider as it rises.
                width: (6 + 2 * Math.min(1, cap.g)) * caps.scale
                height: (13 + 5 * cap.g) * caps.scale
                radius: width / 2
                color: cap.guest && !cap.on ? "transparent"
                     : Qt.tint(Qt.alpha(Theme.accent, cap.used ? (capArea.containsMouse ? 0.6 : 0.42) : (capArea.containsMouse ? 0.4 : 0.22)),
                               Qt.alpha(Theme.accent, Math.max(0, Math.min(1, grow.value))))
                // Guests (from a screen that's gone): hollow, so they read as visiting.
                border.width: cap.guest && !cap.on ? 1.5 : 0
                border.color: Qt.alpha(Theme.accent, capArea.containsMouse ? 0.8 : 0.55)
            }
            MouseArea {
                id: capArea
                anchors.fill: parent
                anchors.margins: -2
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Desktops: every screen switches together (kuwai.desktop).
                onClicked: Hyprland.dispatch(cap.modelData.desktop ? "kuwai.desktop(" + cap.modelData.desktop + ")" : "hl.dsp.focus({workspace = " + JSON.stringify(cap.ws) + "})")
            }
            Tip {
                text: (cap.modelData.desktop ? "Desktop " : "Workspace ") + cap.label + (cap.guest ? " · from the other screen (its home is there)" : "") + (cap.windows ? " · " + cap.windows + (cap.windows === 1 ? " window" : " windows") : " · empty")
                shown: capArea.containsMouse
                below: true
            }
        }
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
}
