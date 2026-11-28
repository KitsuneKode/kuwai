import QtQuick
import qs.config
import qs.components
import "../../services/panelSchema.mjs" as Schema

Column {
    id: bar
    property var buckets: []
    property real total: 0
    property string label: ""
    property int focused: -1
    property bool keys: false
    property int rows: 6
    property int dot: 5
    property int gap: 2
    property bool legend: true
    readonly property real dimTo: 0.28
    signal pointed(int index)

    spacing: Theme.s2

    readonly property var palette: [Theme.green, Theme.cyan, Theme.mint, Theme.indigo, Theme.yellow, Theme.blue, Theme.orange, Theme.textTertiary]
    function colourOf(i) {
        const b = buckets[i];
        if (!b) return Theme.wash(2);
        switch (b.tone) {
        case "muted": return Theme.textTertiary;
        case "info": return Theme.cyan;
        case "good": return Theme.green;
        case "warn": return Theme.orange;
        case "bad": return Theme.red;
        default: return palette[i % palette.length];
        }
    }

    readonly property int cols: Math.max(1, Math.floor((width + gap) / (dot + gap)))
    readonly property int cells: cols * rows
    readonly property var counts: Schema.dotCounts(buckets.map(b => b.value), total, cells)
    readonly property var owner: Schema.dotOwners(counts, cells)

    Item {
        id: field
        width: bar.width
        height: bar.rows * (bar.dot + bar.gap) - bar.gap
        Accessible.role: Accessible.Chart
        Accessible.name: (bar.label ? bar.label + ": " : "") + bar.buckets.map(b => b.label + (b.detail ? ", " + b.detail : "")).join("; ")
        Repeater {
            model: bar.cells
            Rectangle {
                required property int index
                readonly property int part: bar.owner[index]
                x: Math.floor(index / bar.rows) * (bar.dot + bar.gap)
                y: (index % bar.rows) * (bar.dot + bar.gap)
                width: bar.dot; height: bar.dot; radius: bar.dot / 2
                color: part < 0 ? Theme.wash(2) : bar.colourOf(part)
                opacity: part < 0 || bar.focused < 0 || bar.focused === part ? 1 : bar.dimTo
                Behavior on opacity {
                    enabled: !bar.keys && !Theme.reduceMotion
                    NumberAnimation { duration: Theme.hoverMs }
                }
            }
        }
        MouseArea {
            anchors { fill: parent; topMargin: -Theme.s1; bottomMargin: -Theme.s1 }
            hoverEnabled: true
            function at(mx, my) {
                const c = Math.floor(mx / (bar.dot + bar.gap)), r = Math.max(0, Math.min(bar.rows - 1, Math.floor(my / (bar.dot + bar.gap))));
                return bar.owner[Math.max(0, Math.min(bar.cells - 1, c * bar.rows + r))];
            }
            onPositionChanged: mouse => { bar.keys = false; bar.pointed(at(mouse.x, mouse.y)); }
            onExited: if (!bar.keys) bar.pointed(-1)
        }
    }

    Flow {
        visible: bar.legend && bar.buckets.length > 1
        width: bar.width
        spacing: Theme.s1
        Repeater {
            model: bar.buckets
            Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool lit: bar.focused === index
                width: Math.min(chipRow.implicitWidth + Theme.s3, bar.width)
                height: Math.max(Theme.sp(22), chipRow.implicitHeight + Theme.s1 * 2)
                radius: height / 2
                color: lit ? Theme.wash(2) : "transparent"
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Theme.s1 + 1
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: bar.dot + 2; height: width; radius: width / 2; color: bar.colourOf(chip.index) }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, bar.width - bar.dot - Theme.s4)
                        elide: Text.ElideRight
                        text: chip.modelData.label
                        size: Theme.tFootnote
                        color: chip.lit ? Theme.textPrimary : Theme.textSecondary
                    }
                }
                HoverHandler { onHoveredChanged: { bar.keys = false; bar.pointed(hovered ? chip.index : -1); } }
                Accessible.role: Accessible.StaticText
                Accessible.name: chip.modelData.label + (chip.modelData.detail ? ", " + chip.modelData.detail : "")
            }
        }
    }
}
