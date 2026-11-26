// Cleanup: what your agents carry and don't use, and the leftovers on disk
// (bin/kuwai-cleanup). One big number first (Clove's pattern: the cost you
// didn't know you were paying), then the list, then one action.
//
//   Cleanup                                          30 days · 90 · 180
//   7,262
//   tokens every session spends listing 102 skills nobody called in 30 days
//   ▢ next-partial-prefetching-optimizer   Claude, Codex          89
//   …
//   Leftovers   AUR build scratch  6.1 GB   [Move to Trash]
//   [Move 14 to Trash]                                    ⟲ Put back
//
// Nothing is deleted: the Trash, with the skills' links recorded so Put back
// restores both. Keys: ↑↓ choose, Space mark, ⌫ move the marked (press twice),
// U put back, Esc back.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services

FocusScope {
    id: cp
    property bool inStrip: false
    focus: true
    implicitWidth: Theme.panelM
    implicitHeight: view === "projects" ? projects.y + projects.implicitHeight : col.y + col.implicitHeight + 20
    property string view: "skills"
    function takeView() { if (Island.cleanupView) { view = Island.cleanupView; Island.cleanupView = ""; } }
    Connections { target: Island; function onCleanupViewChanged() { cp.takeView(); } }

    property int days: 30
    property var report: null              // (not `data`: that is every Item's children list)
    property bool loading: true
    property string error: ""
    property var marked: ({})
    readonly property int markedCount: Object.keys(marked).length
    property int sel: 0
    property bool keyboard: false
    property Item hoverRow: null
    property bool confirm: false
    property string status: ""
    property bool canPutBack: false
    readonly property var rows: report && report.unused ? report.unused : []

    function load(fresh) {
        loading = true;
        error = "";
        reader.command = [Paths.bin + "/kuwai-cleanup", "--days", String(days)].concat(fresh ? ["--fresh"] : []);
        reader.running = true;
    }
    Component.onCompleted: { takeView(); if (!report) load(false); else loading = false; }
    onDaysChanged: { marked = ({}); confirm = false; load(false); }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try { cp.report = JSON.parse(text); cp.sel = 0; }
                catch (e) { cp.error = "Couldn't read the report"; }
                cp.loading = false;
            }
        }
        onExited: code => { if (code !== 0) { cp.error = "Couldn't look through your agents' skills"; cp.loading = false; } }
    }
    Process {
        id: actor
        property string what: ""
        property int kept: 0
        stdout: StdioCollector { id: actOut }
        onExited: code => {
            if (actor.what === "restore") cp.status = code === 0 ? "Put back" : "Nothing to put back";
            else cp.status = code !== 0 ? "Couldn't move all of " + actor.what
                : "Moved " + actor.what + " to the Trash" + (actor.kept ? "; " + actor.kept + " linked from elsewhere: only the links went" : "");
            cp.canPutBack = code === 0 && actor.what !== "restore";
            cp.marked = ({});
            cp.confirm = false;
            cp.load(true);
        }
    }
    function act(args, what) { actor.what = what; actor.command = [Paths.bin + "/kuwai-cleanup"].concat(args); actor.running = true; }
    function toggle(name) {
        const m = Object.assign({}, marked);
        if (m[name]) delete m[name]; else m[name] = true;
        marked = m;
        confirm = false;
    }
    function markAll() {
        const all = rows.length > 0 && markedCount === rows.length;
        const m = {};
        if (!all) for (const r of rows) m[r.name] = true;
        marked = m;
        confirm = false;
    }
    function trashMarked() {
        if (!markedCount) return;
        if (!confirm) { confirm = true; return; }
        const names = Object.keys(marked);
        const chosen = rows.filter(r => marked[r.name]);
        const paths = [].concat(...chosen.map(r => r.paths || [r.path]));
        const kept = [].concat(...chosen.map(r => r.externalPaths || []));
        actor.kept = kept.length;
        act(["trash"].concat(paths), names.length === 1 ? names[0] : names.length + " skills");
    }
    function num(n) { return Number(n || 0).toLocaleString(Qt.locale("en_US"), "f", 0); }
    function gb(b) { return b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : Math.round(b / 1e6) + " MB"; }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape && confirm) { confirm = false; e.accepted = true; return; }
        if (e.key === Qt.Key_Tab && (e.modifiers & Qt.ControlModifier)) {
            const ids = viewSwitch.options.map(o => o.id);
            view = ids[(ids.indexOf(view) + 1) % ids.length];
            e.accepted = true;
            return;
        }
        if (view !== "skills") return;
        if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) { markAll(); e.accepted = true; return; }
        if ([Qt.Key_Down, Qt.Key_Up, Qt.Key_Space, Qt.Key_Delete, Qt.Key_Backspace].indexOf(e.key) >= 0) keyboard = true;
        if (e.key === Qt.Key_Down) sel = Math.min(rows.length - 1, sel + 1);
        else if (e.key === Qt.Key_Up) sel = Math.max(0, sel - 1);
        else if (e.key === Qt.Key_Space && rows[sel]) toggle(rows[sel].name);
        else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) trashMarked();
        else if (e.key === Qt.Key_U && canPutBack) act(["restore"], "restore");
        else return;
        list.positionViewAtIndex(sel, ListView.Contain);
        e.accepted = true;
    }

    Segmented {
        id: viewSwitch
        x: 20; y: cp.inStrip ? Theme.s2 : 20
        options: [{ id: "skills", label: "Skills" }, { id: "projects", label: "Idle projects" }]
            .concat(cp.report && cp.report.leftovers && cp.report.leftovers.length ? [{ id: "leftovers", label: "Leftovers" }] : [])
        current: cp.view
        onPicked: id => cp.view = id
    }
    Segmented {
        id: daysSwitch
        readonly property bool below: viewSwitch.width + width + 56 > cp.width
        visible: cp.view === "skills"
        x: below ? 20 : cp.width - 20 - width
        y: below ? viewSwitch.y + viewSwitch.height + Theme.s2 : viewSwitch.y
        options: [{ id: "30", label: "30 days" }, { id: "90", label: "90" }, { id: "180", label: "180" }]
        current: String(cp.days)
        onPicked: id => cp.days = Number(id)
    }
    Loader {
        id: projects
        y: viewSwitch.y + viewSwitch.height
        width: cp.width
        active: cp.view === "projects"
        visible: active
        focus: active
        sourceComponent: SweepPanel {}
    }
    Column {
        id: col
        x: 20; y: (daysSwitch.visible && daysSwitch.below ? daysSwitch.y + daysSwitch.height : viewSwitch.y + viewSwitch.height) + 10
        visible: cp.view === "skills" || cp.view === "leftovers"
        width: cp.width - 40
        spacing: 14

        // ── The number ──────────────────────────────────────────────────
        Column {
            id: theNumber
            visible: cp.view === "skills"
            width: parent.width
            spacing: 2
            Label {
                // No number when there is none: a failed look showed "0" in the
                // big face, which reads as "nothing to clean".
                visible: !(cp.error && !cp.report)
                text: cp.loading && !cp.report ? "…" : cp.num(cp.report ? cp.report.unusedTokens : 0)
                size: Theme.tClock * 2 - 8; weight: Theme.wBold; rounded: true
                tabular: true
            }
            Ui.Notice {
                visible: cp.error !== ""
                glyph: "\u{f0026}"
                title: cp.error
                action: "Try again"
                onActed: cp.load(true)
            }
            Label {
                visible: !cp.error
                width: parent.width
                wrapMode: Text.Wrap
                text: !cp.report ? "Reading your agents' transcripts…"
                    : cp.report.unused.length === 0 ? "tokens: every skill was used in the last " + cp.days + " days. Nothing to clear."
                    : "tokens each session spends on " + cp.report.unused.length + " skills unused in " + cp.days + " days · "
                      + cp.num(cp.report.listTokens) + " for all " + cp.report.skills
                size: Theme.tSub; color: Theme.textSecondary
            }
        }

        // ── The skills nobody used ──────────────────────────────────────
        // More that way: the rows fade, and a thumb shows while it scrolls.
        ScrollFade { flickable: list }
        ScrollHint { flickable: list; inside: true }
        ListView {
            id: list
            visible: cp.view === "skills" && cp.rows.length > 0
            width: parent.width
            // Room for the leftovers and the action under it (the island has a ceiling).
            height: Math.min(contentHeight, Math.max(2 * (Theme.sp(44) + 2), Theme.panelMaxH - (cp.inStrip ? 34 : 0) - col.y - 20
                                - theNumber.height - (leftovers.visible ? leftovers.height + col.spacing : 0) - action.height - 2 * col.spacing))
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: cp.rows
            FluidHighlight {
                parent: list.contentItem
                radius: Theme.r2
                target: cp.keyboard ? list.itemAtIndex(cp.sel) : cp.hoverRow
                ring: cp.keyboard
            }
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: !!cp.marked[modelData.name]
                width: list.width
                height: Theme.sp(44)
                Accessible.role: Accessible.CheckBox
                Accessible.name: modelData.name + ", " + modelData.tokens + " tokens a session" + (on ? ", marked" : "")
                Accessible.checked: on
                // The mark: a box, filled when marked.
                Rectangle {
                    id: box
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16; radius: 4
                    color: row.on ? Theme.accent : "transparent"
                    border.width: row.on ? 0 : 1.5
                    border.color: Theme.edge(4)
                    Behavior on color { ColorAnimation { duration: Theme.microMs } }
                    Text {
                        anchors.centerIn: parent
                        visible: row.on
                        text: "\u{f012c}"
                        font.family: Theme.fontGlyph; font.pixelSize: 11
                        color: Theme.onAccent
                    }
                }
                Column {
                    anchors { left: box.right; leftMargin: 12; right: cost.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Label { width: parent.width; elide: Text.ElideRight; text: row.modelData.name; size: Theme.tBody; weight: Theme.wMedium }
                    Label {
                        width: parent.width; elide: Text.ElideRight
                        text: (row.modelData.agents.length ? row.modelData.agents.join(", ") : "Every agent that reads ~/.agents")
                            + (row.modelData.copies > 1 ? " · " + row.modelData.copies + " copies" : "")
                        size: Theme.tFootnote; color: Theme.textTertiary
                    }
                }
                Label {
                    id: cost
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: row.modelData.tokens + " tokens"
                    size: Theme.tSub; color: Theme.textSecondary
                    tabular: true
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered) { cp.keyboard = false; cp.sel = row.index; cp.hoverRow = row; }
                        else if (cp.hoverRow === row) cp.hoverRow = null;
                    }
                }
                TapHandler { onTapped: cp.toggle(row.modelData.name) }
                Accessible.onPressAction: cp.toggle(row.modelData.name)
                Accessible.onToggleAction: cp.toggle(row.modelData.name)
            }
        }

        // ── Leftovers on disk ───────────────────────────────────────────
        Column {
            id: leftovers
            visible: cp.view === "leftovers" && !!cp.report && cp.report.leftovers.length > 0
            width: parent.width
            spacing: 6
            Label { leftPadding: 10; text: "Leftovers"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textTertiary }
            Repeater {
                model: cp.report ? cp.report.leftovers : []
                delegate: Item {
                    id: lo
                    required property var modelData
                    width: parent.width
                    height: Math.max(Theme.sp(36), loText.implicitHeight + Theme.s2)
                    Column {
                        id: loText
                        anchors { left: parent.left; leftMargin: 10; right: loAct.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Label { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: lo.modelData.label + "  ·  " + cp.gb(lo.modelData.bytes); size: Theme.tBody; weight: Theme.wMedium }
                        Label { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; text: lo.modelData.detail; size: Theme.tFootnote; color: Theme.textTertiary }
                    }
                    Ui.Button {
                        id: loAct
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        kind: "secondary"
                        text: lo.modelData.safe ? "Move to Trash" : "Show"
                        onClicked: lo.modelData.safe ? cp.act(["trash-path"].concat(lo.modelData.paths), lo.modelData.label.toLowerCase())
                                                     : Apps.open(lo.modelData.paths[0])
                    }
                }
            }
        }

        // ── The action ──────────────────────────────────────────────────
        Item {
            id: action
            visible: cp.view === "skills"
            width: parent.width
            height: 34
            Ui.Button {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                visible: cp.markedCount > 0
                kind: cp.confirm ? "danger" : "primary"
                text: cp.confirm ? "Press again to move " + cp.markedCount + " to the Trash" : "Move " + cp.markedCount + " to Trash"
                onClicked: cp.trashMarked()
            }
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                visible: cp.markedCount === 0
                text: cp.status || (cp.rows.length ? "Click a skill (or Space) to mark it" : "")
                size: Theme.tSub; color: Theme.textSecondary
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: Theme.s1
                Ui.Button {
                    visible: cp.rows.length > 1
                    kind: "quiet"
                    text: cp.markedCount === cp.rows.length ? "Mark none" : "Mark all " + cp.rows.length
                    onClicked: cp.markAll()
                }
                Ui.Button {
                    visible: cp.canPutBack
                    kind: "secondary"
                    glyph: "\u{f054d}"
                    text: "Put back"
                    onClicked: cp.act(["restore"], "restore")
                }
            }
        }
    }
}
