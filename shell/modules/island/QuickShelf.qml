// Quick switches, one at a time: the pinned switch (Caffeine by default) sits
// in the hover view; click toggles it. Press and hold (or right-click) and a
// shelf grows out of it toward the middle with all of them, bigger:
//
//              ╭──────────────────────────────────────╮
//   … 20:23    │  ☕   🎙   🔈   ☾   ☀                  │ ← the shelf
//              ╰──────────────────────────────────────╯
//                                                    ☕   ← the trigger
//
// The shelf stays while the pointer is on it or the trigger, and folds away
// 450 ms after it leaves both (crossing a gap doesn't close it). Hold a
// switch in the shelf to pin it as the one shown. Another switch in a
// non-default state (mic muted, Focus on) puts a dot on the trigger, so
// nothing important hides in there.
//
// More switches: one entry in `items` (IslandHover). The shelf is a row; it
// stays tidy to 7–8 before it would want a second line.
//
// Motion (Emil): the hold ring fills linearly for 350 ms (deliberate) and
// snaps back in 140 ms; the shelf opens in 200 ms ease-out from the trigger's
// side (not its centre), the switches following 25 ms apart; it closes in
// 120 ms, all together. Reduced motion: it just appears and goes.
import QtQuick
import QtQuick.Effects
import qs.config
import qs.components

Item {
    id: shelf
    // [{ id, glyph, glyphOff, on, tone, offTone, tip, alert, toggle(), wheel(steps) }]
    property var items: []
    readonly property string primaryId: Settings.quickPrimary || "caffeine"
    readonly property var primary: items.find(i => i.id === primaryId) || items[0] || null
    readonly property var alerts: items.filter(i => primary && i.id !== primary.id && i.alert)
    property bool open: false

    implicitWidth: 26
    implicitHeight: 26

    QuickIcon {
        id: trigger
        anchors.fill: parent
        visible: !!shelf.primary
        holdable: true
        glyph: shelf.primary ? shelf.primary.glyph : ""
        glyphOff: shelf.primary ? (shelf.primary.glyphOff || "") : ""
        on: !!shelf.primary && shelf.primary.on
        tone: shelf.primary ? shelf.primary.tone : Theme.textPrimary
        offTone: shelf.primary && shelf.primary.offTone ? shelf.primary.offTone : Theme.textTertiary
        tip: shelf.open || !shelf.primary ? "" : shelf.primary.tip + " · hold for more"
        badge: shelf.alerts.length > 0 && !shelf.open
        badgeTone: shelf.alerts.length ? (shelf.alerts[0].tone || Theme.red) : Theme.red
        onClicked: if (shelf.primary) shelf.primary.toggle()
        onHeld: shelf.open = !shelf.open
        onWheel: steps => { if (shelf.primary && shelf.primary.wheel) shelf.primary.wheel(steps); }
    }
    HoverHandler { id: triggerHover }

    // Fold away a moment after the pointer leaves both.
    readonly property bool inside: triggerHover.hovered || panelHover.hovered
    onInsideChanged: if (inside) leave.stop(); else if (open) leave.restart()
    Timer { id: leave; interval: 450; onTriggered: if (!shelf.inside) shelf.open = false }

    Item {
        id: panel
        z: 50
        property real reveal: shelf.open ? 1 : 0
        Behavior on reveal {
            enabled: !Theme.reduceMotion
            NumberAnimation { duration: shelf.open ? 200 : 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
        visible: reveal > 0.01
        // Grows out of the trigger: its right edge sits on the trigger's.
        anchors { right: trigger.right; rightMargin: -6; verticalCenter: trigger.verticalCenter }
        width: row.implicitWidth + 14
        height: 44
        opacity: Math.min(1, reveal * 1.6)
        transform: Scale {
            origin.x: panel.width; origin.y: panel.height / 2
            xScale: 0.9 + 0.1 * panel.reveal; yScale: 0.94 + 0.06 * panel.reveal
        }

        RectangularShadow {
            anchors.fill: bg; radius: bg.radius
            offset.y: 8; blur: 24; spread: -6
            color: Qt.rgba(0, 0, 0, 0.45 * panel.reveal)
        }
        Rectangle {
            id: bg
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(0.1, 0.1, 0.11, 0.98)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: shelf.items
                QuickIcon {
                    id: sw
                    required property var modelData
                    required property int index
                    width: 34; height: 34
                    glyphSize: 17
                    holdable: true
                    glyph: modelData.glyph
                    glyphOff: modelData.glyphOff || ""
                    on: modelData.on
                    tone: modelData.tone
                    offTone: modelData.offTone || Theme.textTertiary
                    tip: modelData.tip + (shelf.primary && shelf.primary.id === modelData.id ? " · pinned" : " · hold to pin")
                    onClicked: modelData.toggle()
                    onHeld: { Settings.set("quickPrimary", modelData.id); shelf.open = false; }
                    onWheel: steps => { if (modelData.wheel) modelData.wheel(steps); }
                    // Nearest the trigger first; 25 ms apart.
                    readonly property real lag: (shelf.items.length - 1 - index) * 0.12
                    readonly property real t: Theme.reduceMotion || !shelf.open ? panel.reveal : Math.max(0, Math.min(1, (panel.reveal - lag) / Math.max(0.2, 1 - lag)))
                    opacity: t
                    transform: Translate { x: (1 - sw.t) * 8 }
                }
            }
        }
        HoverHandler { id: panelHover }
    }
}
