// A total split into parts, drawn as a field of dots, with its legend (after
// Clove's storage bar). Hovering a part, in the bar or in the legend, lights
// it in both and rewrites the line above: the chart explains itself where you
// look, instead of a tooltip. One big number on top (the whole), the parts
// below.
//
//   LinkedBar {
//       big: "9.1 GB"; caption: "of 24 GB in use"
//       parts: [{ label: "Zen", value: 2.9, color: Theme.orange, detail: "20 processes" }, …]
//       total: 24                       // parts may not fill it: the rest is empty dots
//   }
//
// Dots fill column by column (left to right, top to bottom within a column),
// so each part is a block you can point at. Values change in place (no
// re-layout animation): it's a reading.
import QtQuick
import qs.config

Column {
    id: lb
    property string title: ""                  // the card's own label, as the Meters above it have
    property string big: ""
    property string caption: ""
    property var parts: []
    property real total: 1
    property int rows: 6
    property int dot: 5
    property int gap: 2
    property int hot: -1                       // the part under the pointer (bar or legend)
    property string unit: ""
    function fmt(v) { return v >= 10 ? Math.round(v) + unit : v.toFixed(1) + unit; }

    spacing: 8

    readonly property int cols: Math.max(1, Math.floor((width + gap) / (dot + gap)))
    readonly property int cells: cols * rows
    // Cell → part index (-1 empty), part blocks in order.
    readonly property var owner: {
        const out = new Array(cells).fill(-1);
        let at = 0;
        for (let i = 0; i < parts.length; i++) {
            const n = Math.round(Math.max(0, parts[i].value) / Math.max(total, 1e-9) * cells);
            for (let k = 0; k < n && at < cells; k++) out[at++] = i;
        }
        return out;
    }

    // ── The number, and the line that becomes the hovered part ─────────
    Column {
        width: lb.width
        spacing: 1
        Label { visible: lb.title !== ""; text: lb.title; size: 12; color: Theme.textSecondary; bottomPadding: 4 }
        Label {
            text: lb.hot >= 0 && lb.parts[lb.hot] ? lb.fmt(lb.parts[lb.hot].value) : lb.big
            size: Theme.tTitle1; weight: Theme.wBold; rounded: true
            color: lb.hot >= 0 && lb.parts[lb.hot] ? lb.parts[lb.hot].color : Theme.textPrimary
            font.features: ({ "tnum": 1 })
        }
        Label {
            width: parent.width
            elide: Text.ElideRight
            text: lb.hot >= 0 && lb.parts[lb.hot] ? lb.parts[lb.hot].label + (lb.parts[lb.hot].detail ? "  ·  " + lb.parts[lb.hot].detail : "") : lb.caption
            size: Theme.tSub; color: Theme.textSecondary
        }
    }

    // ── The dots ───────────────────────────────────────────────────────
    Item {
        width: lb.width
        height: lb.rows * (lb.dot + lb.gap) - lb.gap
        Repeater {
            model: lb.cells
            Rectangle {
                required property int index
                readonly property int col: Math.floor(index / lb.rows)
                readonly property int row: index % lb.rows
                readonly property int part: lb.owner[index]
                x: col * (lb.dot + lb.gap); y: row * (lb.dot + lb.gap)
                width: lb.dot; height: lb.dot; radius: lb.dot / 2
                color: part < 0 ? Qt.rgba(1, 1, 1, 0.08) : lb.parts[part].color
                opacity: lb.hot < 0 || part === lb.hot ? 1 : 0.28
                Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
            }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: mouse => {
                const c = Math.floor(mouse.x / (lb.dot + lb.gap)), r = Math.min(lb.rows - 1, Math.floor(mouse.y / (lb.dot + lb.gap)));
                lb.hot = lb.owner[Math.max(0, Math.min(lb.cells - 1, c * lb.rows + r))];
            }
            onExited: lb.hot = -1
        }
    }

    // ── The legend: the same parts, lit together ───────────────────────
    Flow {
        width: lb.width
        spacing: 4
        Repeater {
            model: lb.parts
            Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool lit: lb.hot === index
                width: chipRow.implicitWidth + 14; height: 22; radius: 11
                color: Qt.rgba(1, 1, 1, lit ? 0.12 : 0)
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 5
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5; color: chip.modelData.color }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.label; size: Theme.tFootnote; color: chip.lit ? Theme.textPrimary : Theme.textSecondary }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: lb.fmt(chip.modelData.value); size: Theme.tFootnote; color: Theme.textTertiary; font.features: ({ "tnum": 1 }) }
                }
                HoverHandler { onHoveredChanged: lb.hot = hovered ? chip.index : (lb.hot === chip.index ? -1 : lb.hot) }
                Accessible.role: Accessible.StaticText
                Accessible.name: chip.modelData.label + " " + lb.fmt(chip.modelData.value)
            }
        }
    }
}
