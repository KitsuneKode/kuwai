// A unified diff, the way good code review tools draw one (GitHub, diffs.com):
// both line numbers in a quiet gutter, + and − rows on a soft green / red
// wash with a stronger edge, each hunk introduced by its @@ context, and
// unchanged context in plain text. Lines flagged as worth a look carry an
// orange bar and their reason; routine changes (only a version or a
// checksum moved) are marked as such, so the eye goes to what matters.
//
//   DiffView { file: review.files[0]; flags: review.flags }
//
// `file` is one entry of rice-update's review JSON: { path, status, add, del,
// binary, hunks: [{ header, context, lines: [{ t: "+"|"-"|" ", o, n, s, routine }] }] }.
// Scrolls both ways; long lines aren't wrapped (code reads by columns).
import QtQuick
import qs.config

Item {
    id: dv
    property var file: null
    property var flags: []
    property int fontSize: 11
    readonly property real rowH: Math.round(fontSize * 1.65)
    readonly property real charW: metrics.advanceWidth
    // Line → its flag reason, for this file.
    readonly property var flagged: {
        const m = {};
        for (const f of (flags || [])) if (file && f.path === file.path && f.line) m[f.line] = f.why;
        return m;
    }
    // Hunks flattened into rows: { kind: "hunk"|"line", … }.
    readonly property var rows: {
        const out = [];
        if (!file || !file.hunks) return out;
        for (const h of file.hunks) {
            out.push({ kind: "hunk", text: h.context || h.header });
            for (const l of h.lines) out.push({ kind: "line", t: l.t, o: l.o, n: l.n, s: l.s, routine: !!l.routine });
        }
        return out;
    }
    readonly property int longest: rows.reduce((m, r) => Math.max(m, (r.s || r.text || "").length), 0)
    readonly property real gutterW: Math.max(2, String(rows.reduce((m, r) => Math.max(m, r.o || 0, r.n || 0), 0)).length) * charW * 2 + 26
    function scrollToLine(n) {
        const i = rows.findIndex(r => r.kind === "line" && r.n === n);
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center);
    }

    TextMetrics { id: metrics; font.family: Theme.fontMono; font.pixelSize: dv.fontSize; text: "M" }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
    }

    Text {
        visible: !!(dv.file && dv.file.binary)
        anchors.centerIn: parent
        text: "Binary file: not shown"
        font.family: Theme.fontText; font.pixelSize: 12
        color: Theme.textTertiary
    }

    ListView {
        id: list
        anchors { fill: parent; margins: 1 }
        clip: true
        model: dv.rows
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        contentWidth: Math.max(width, dv.gutterW + dv.longest * dv.charW + 40)
        reuseItems: true

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var r: modelData
            readonly property bool add: r.kind === "line" && r.t === "+"
            readonly property bool del: r.kind === "line" && r.t === "-"
            readonly property string why: add && r.n ? (dv.flagged[r.n] || "") : ""
            width: list.contentWidth
            height: r.kind === "hunk" ? dv.rowH + 6 : dv.rowH

            // Hunk header: where in the file this is.
            Rectangle {
                visible: row.r.kind === "hunk"
                anchors.fill: parent
                anchors.topMargin: row.index === 0 ? 0 : 4
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                Text {
                    x: list.contentX + 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⋯  " + (row.r.text || "")
                    font.family: Theme.fontMono; font.pixelSize: dv.fontSize
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85)
                }
            }

            // Changed lines: a wash across, a stronger edge at the left.
            Rectangle {
                visible: row.add || row.del
                anchors.fill: parent
                color: row.why ? Qt.rgba(1, 0.62, 0.04, 0.13)
                     : row.add ? Qt.rgba(0.19, 0.82, 0.35, row.r.routine ? 0.07 : 0.13)
                     : Qt.rgba(1, 0.27, 0.23, 0.12)
                Rectangle {
                    x: list.contentX
                    width: 3; height: parent.height
                    color: row.why ? Theme.orange : row.add ? Qt.rgba(0.19, 0.82, 0.35, row.r.routine ? 0.45 : 0.9) : Qt.rgba(1, 0.27, 0.23, 0.8)
                }
            }

            // Gutter: old and new line numbers, pinned while scrolling sideways.
            Item {
                visible: row.r.kind === "line"
                x: list.contentX
                width: dv.gutterW; height: parent.height
                z: 2
                Rectangle {
                    anchors.fill: parent
                    color: row.add ? Qt.rgba(0.05, 0.12, 0.07, 1) : row.del ? Qt.rgba(0.14, 0.05, 0.05, 1) : Qt.rgba(0.05, 0.05, 0.06, 1)
                    opacity: 0.92
                }
                Text {
                    x: 8; width: (dv.gutterW - 26) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: row.r.o || ""
                    font.family: Theme.fontMono; font.pixelSize: dv.fontSize - 1
                    color: Qt.rgba(1, 1, 1, 0.28)
                }
                Text {
                    x: 8 + (dv.gutterW - 26) / 2 + 4; width: (dv.gutterW - 26) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: row.r.n || ""
                    font.family: Theme.fontMono; font.pixelSize: dv.fontSize - 1
                    color: Qt.rgba(1, 1, 1, 0.28)
                }
                Text {
                    x: dv.gutterW - 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.r.t === " " ? "" : row.r.t
                    font.family: Theme.fontMono; font.pixelSize: dv.fontSize
                    color: row.add ? Theme.green : Theme.red
                }
            }

            // The code itself.
            Text {
                visible: row.r.kind === "line"
                x: dv.gutterW + 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.r.s || " "
                textFormat: Text.PlainText
                font.family: Theme.fontMono; font.pixelSize: dv.fontSize
                color: row.del ? Qt.rgba(1, 0.86, 0.85, 0.82) : row.add ? Qt.rgba(0.88, 1, 0.9, 0.95) : Theme.textSecondary
            }
            // Why it's flagged / that it's routine, at the right edge.
            Rectangle {
                visible: !!row.why || (row.add && row.r.routine)
                anchors { right: parent.right; rightMargin: list.contentWidth - list.contentX - list.width + 8; verticalCenter: parent.verticalCenter }
                height: dv.rowH - 4; radius: height / 2
                width: tag.implicitWidth + 14
                color: row.why ? Qt.rgba(1, 0.62, 0.04, 0.22) : Qt.rgba(1, 1, 1, 0.07)
                z: 3
                Text {
                    id: tag
                    anchors.centerIn: parent
                    text: row.why || "version bump"
                    font.family: Theme.fontText; font.pixelSize: dv.fontSize - 1; font.weight: Theme.wMedium
                    color: row.why ? Theme.orange : Theme.textTertiary
                }
            }
        }
    }
    ScrollHint { flickable: list; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 2 } }
}
