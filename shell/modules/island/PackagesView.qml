import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui
import qs.services
import "../../services/links.mjs" as Links
import "../../services/sizes.mjs" as Sizes

Item {
    id: pv
    property var list: null
    property bool pinned: false
    property string filter: ""
    property string kind: "all"
    property string open: ""
    readonly property var shown: {
        const q = filter.trim().toLowerCase();
        return (list || []).filter(p => (kind === "all" || (kind === "aur" && p.aur) || (kind === "held" && Updates.isHeld(p.name)))
            && (!q || p.name.indexOf(q) >= 0 || String(p.desc || "").toLowerCase().indexOf(q) >= 0));
    }
    function mb(b) { return Sizes.bytes(b); }
    function load() { if (!pinned && !reader.running) reader.running = true; }
    onVisibleChanged: if (visible && !list) load()
    Process {
        id: reader
        command: [Paths.bin + "/kuwai-pkgs", "installed"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); if (Array.isArray(d)) pv.list = d; } catch (e) {} } }
    }

    Column {
        id: head
        x: Theme.s5; y: Theme.s4
        width: pv.width - Theme.s5 * 2
        spacing: Theme.s3
        Item {
            width: parent.width; height: Math.max(Theme.sp(30), title.implicitHeight)
            Label { id: title; anchors.verticalCenter: parent.verticalCenter; text: "Your packages"; size: Theme.tTitle3; weight: Theme.wSemibold }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: !pv.list ? "Reading…" : pv.shown.length + " of " + pv.list.length + (Object.keys(Updates.held).length ? " · " + Object.keys(Updates.held).length + " held" : "")
                size: Theme.tFootnote; color: Theme.textTertiary
                tabular: true
            }
        }
        Rectangle {
            width: parent.width; height: Theme.sp(34); radius: Theme.r2
            color: Theme.wash(1)
            border.width: 1; border.color: field.activeFocus ? Theme.accent : Theme.cardEdge
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: Theme.s3; rightMargin: Theme.s3 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.textPrimary
                font.family: Theme.fontText; font.pixelSize: Theme.tBody
                selectByMouse: true
                onTextChanged: pv.filter = text
                Keys.onEscapePressed: event => { if (text) { text = ""; event.accepted = true; } else event.accepted = false; }
            }
            Label {
                visible: field.text === ""
                anchors { left: parent.left; leftMargin: Theme.s3; verticalCenter: parent.verticalCenter }
                text: "Filter by name or description"
                size: Theme.tBody; color: Theme.textTertiary
            }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Filter packages"
        }
        Segmented {
            width: parent.width
            options: [{ id: "all", label: "Installed" }, { id: "aur", label: "AUR" }, { id: "held", label: "Held" }]
            current: pv.kind
            onPicked: id => pv.kind = id
        }
    }

    ListView {
        id: rows
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: note.top; topMargin: Theme.s3; leftMargin: Theme.s5; rightMargin: Theme.s5; bottomMargin: Theme.s2 }
        clip: true
        spacing: Theme.s1
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: pv.shown; objectProp: "name" }
        property Item hoverRow: null
        FluidHighlight { parent: rows.contentItem; target: rows.hoverRow; radius: Theme.r2 }
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool expanded: pv.open === modelData.name
            readonly property bool held: Updates.isHeld(modelData.name)
            width: rows.width
            height: Math.max(Theme.sp(46), top.implicitHeight + Theme.s2 * 2) + (expanded ? more.implicitHeight + Theme.s2 : 0)
            radius: Theme.r2
            color: expanded ? Theme.wash(1) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
            HoverHandler {
                id: rowHover
                onHoveredChanged: {
                    if (hovered && !row.expanded) rows.hoverRow = row;
                    else if (rows.hoverRow === row) rows.hoverRow = null;
                }
            }
            onExpandedChanged: if (expanded && rows.hoverRow === row) rows.hoverRow = null
            TapHandler { onTapped: pv.open = row.expanded ? "" : row.modelData.name }
            Accessible.role: Accessible.Button
            Accessible.name: row.modelData.name + " " + row.modelData.version + (row.held ? ", held" : "")
            Accessible.onPressAction: pv.open = row.expanded ? "" : row.modelData.name
            Column {
                id: top
                x: Theme.s3; y: Theme.s2
                width: parent.width - x - lock.width - Theme.s3 * 2
                spacing: 1
                Row {
                    width: parent.width
                    spacing: Theme.s2
                    Label { id: nm; width: Math.min(implicitWidth, parent.width - ver.width - (aurChip.visible ? aurChip.width + Theme.s2 : 0) - Theme.s2); elide: Text.ElideRight; text: row.modelData.name; size: Theme.tBody; weight: Theme.wMedium }
                    Label { id: ver; anchors.baseline: nm.baseline; text: row.modelData.version; size: Theme.tFootnote; color: Theme.textTertiary; tabular: true }
                    Chip { id: aurChip; visible: row.modelData.aur; anchors.verticalCenter: nm.verticalCenter; text: "AUR" }
                }
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: (row.held ? "Held at " + (Updates.held[row.modelData.name].version || row.modelData.version) + " · " : "") + (row.modelData.desc || "")
                    size: Theme.tFootnote; color: Theme.textSecondary
                }
            }
            Rectangle {
                id: lock
                anchors { right: parent.right; rightMargin: Theme.s3; top: parent.top; topMargin: Theme.s2 }
                width: Theme.sp(30); height: width; radius: width / 2
                color: row.held ? Theme.pillHover : lockHover.hovered ? Theme.pillHover : Theme.pill
                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: row.held ? "\u{f033e}" : "\u{f0fc6}"
                    font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphM
                    color: row.held ? Theme.textPrimary : Theme.textSecondary
                }
                HoverHandler { id: lockHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Updates.setHeld(row.modelData.name, !row.held) }
                Accessible.role: Accessible.CheckBox
                Accessible.checked: row.held
                Accessible.name: (row.held ? "Let go of " : "Hold ") + row.modelData.name
                Accessible.onPressAction: Updates.setHeld(row.modelData.name, !row.held)
            }
            Column {
                id: more
                visible: row.expanded
                x: Theme.s3; y: top.y + top.implicitHeight + Theme.s2
                width: parent.width - Theme.s3 * 2
                spacing: Theme.s1
                Repeater {
                    model: !row.expanded ? [] : [
                        ["Size", pv.mb(row.modelData.size || 0)],
                        ["Installed", row.modelData.installed || ""],
                        ["Licence", (row.modelData.licenses || []).join(", ")],
                        ["Needs", (row.modelData.depends || []).length ? (row.modelData.depends || []).length + ": " + row.modelData.depends.slice(0, 8).join(", ") + (row.modelData.depends.length > 8 ? "…" : "") : "nothing"],
                        ["Needed by", (row.modelData.requiredBy || []).join(", ") || "nothing you installed depends on it"]
                    ].filter(x => x[1])
                    delegate: Row {
                        required property var modelData
                        width: more.width
                        spacing: Theme.s2
                        Label { width: Theme.sp(76); text: modelData[0]; size: Theme.tFootnote; color: Theme.textTertiary }
                        Label { width: parent.width - Theme.sp(76) - Theme.s2; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; text: modelData[1]; size: Theme.tFootnote; color: Theme.textSecondary }
                    }
                }
                Row {
                    spacing: Theme.s2
                    Button {
                        visible: Links.webLink(row.modelData.url || "") !== ""
                        height: Theme.sp(28); size: Theme.tFootnote
                        text: "Project page"
                        onClicked: { Apps.open(Links.webLink(row.modelData.url)); Island.close(); }
                    }
                    Button {
                        height: Theme.sp(28); size: Theme.tFootnote
                        text: row.held ? "Let it update" : "Hold at " + row.modelData.version
                        onClicked: Updates.setHeld(row.modelData.name, !row.held)
                    }
                }
            }
        }
    }
    ScrollFade { flickable: rows }
    Label {
        id: note
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: Theme.s5; rightMargin: Theme.s5; bottomMargin: Theme.s4 }
        wrapMode: Text.Wrap
        text: "A held package stays at its version on every update (pacman --ignore). Arch updates the rest together; if a held one would break what depends on it, pacman stops before changing anything."
        size: Theme.tCaption; color: Theme.textTertiary
    }
}
