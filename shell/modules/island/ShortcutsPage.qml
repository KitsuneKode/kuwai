import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.components.ui
import qs.services
import "../../services/keychord.mjs" as KC

Column {
    id: page
    spacing: 18

    property string filter: ""
    property Item returnTo: null
    property bool captured: false
    readonly property var groups: KC.groupsOf(KeyBinds.entries, filter)

    Component.onCompleted: KeyBinds.load()
    Component.onDestruction: stop(false)
    onVisibleChanged: if (!visible) stop(false)

    function edit(e, from) {
        if (!e || e.fixed || KeyBinds.busy) return;
        returnTo = from || null;
        KeyBinds.editing = e.aid;
        KeyBinds.pending = null;
        KeyBinds.error = "";
        captured = true;
        Hyprland.dispatch("hl.dsp.submap('kuwai_capture')");
        catcher.forceActiveFocus();
    }
    function release() {
        if (captured) Hyprland.dispatch("hl.dsp.submap('reset')");
        captured = false;
    }
    function stop(refocus) {
        release();
        if (!KeyBinds.editing) return;
        KeyBinds.editing = "";
        KeyBinds.pending = null;
        if (refocus && returnTo) returnTo.forceActiveFocus();
    }
    function save() {
        if (!KeyBinds.canSave) return;
        release();
        KeyBinds.save();
        if (returnTo) returnTo.forceActiveFocus();
    }
    function none() {
        const e = KeyBinds.editEntry;
        if (!e || !e.keys || KeyBinds.busy) return;
        stop(true);
        KeyBinds.none(e);
    }
    function chordText(keys) { return KC.caps(keys).join("+"); }
    function rowDetail(e) {
        if (KeyBinds.editing === e.aid) {
            const p = KeyBinds.pending, c = KeyBinds.clash;
            if (!p) return "Press the new keys · Esc cancels" + (e.keys && e.text !== "Lock" ? " · ⌫ leaves it without one" : "");
            if (p.why) return p.why;
            if (c && c.kind === "same") return "That's already its shortcut";
            if (c && c.kind === "kuwai") return "Now “" + c.text + "”: Replace leaves that one without a shortcut";
            if (c) return c.text ? "Taken by “" + c.text + "”, which can't be moved from here" : "Taken by a shortcut of your own";
            return "↵ saves · Esc cancels";
        }
        const t = e.custom ? KeyBinds.takenBy(e) : null;
        return [e.sub, e.keys ? "" : "No shortcut",
                e.custom ? "Yours; default " + chordText(e.def) + (t ? " (now “" + t.text + "”)" : "") : "",
                e.fixed ? "Held, so it stays as it is" : ""].filter(x => x).join(" · ");
    }

    Item {
        id: catcher
        width: 0; height: 0
        Accessible.role: Accessible.EditableText
        Accessible.name: KeyBinds.editEntry ? "New shortcut for " + KeyBinds.editEntry.text : ""
        Accessible.description: KeyBinds.editEntry ? page.rowDetail(KeyBinds.editEntry) : ""
        onActiveFocusChanged: if (!activeFocus && KeyBinds.editing) lost.restart()
        Keys.onPressed: ev => {
            ev.accepted = true;
            const bare = !(ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier));
            if (bare && ev.key === Qt.Key_Escape) { page.stop(true); return; }
            if (bare && (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && KeyBinds.pending) { page.save(); return; }
            if (bare && (ev.key === Qt.Key_Backspace || ev.key === Qt.Key_Delete)) { if (KeyBinds.editEntry && KeyBinds.editEntry.text !== "Lock") page.none(); return; }
            if (ev.isAutoRepeat) return;
            const c = KC.chordOf(ev.key, ev.modifiers, ev.nativeScanCode);
            if (c) KeyBinds.pending = c;
        }
        Keys.onReleased: ev => { ev.accepted = true; }
    }
    Timer { id: lost; interval: 250; onTriggered: if (!catcher.activeFocus) page.stop(false) }

    SettingsGroup {
        SettingsRow {
            label: "Find a shortcut"
            detail: !KeyBinds.loaded ? "Reading Hyprland's shortcuts…"
                : KeyBinds.failed || !KeyBinds.entries.length ? "Hyprland didn't list kuwai's shortcuts"
                : KeyBinds.entries.length + " shortcuts" + (KeyBinds.changed ? ", " + KeyBinds.changed + " of them yours" : ", all as they came")
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: Theme.sp(180)
                Layout.maximumWidth: Theme.sp(180)
                implicitHeight: Theme.sp(30)
                radius: Theme.r1
                color: field.activeFocus ? Theme.wash(3) : Theme.wash(1)
                border.width: 1
                border.color: field.activeFocus ? Theme.edge(3) : Theme.edge(0)
                TextInput {
                    id: field
                    anchors { fill: parent; leftMargin: Theme.s3; rightMargin: Theme.s3 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    selectionColor: Qt.alpha(Theme.accent, 0.4)
                    font.family: Theme.fontText
                    font.pixelSize: Theme.sp(Theme.tSub)
                    font.variableAxes: Theme.axesFor(Theme.tSub)
                    clip: true
                    activeFocusOnTab: true
                    onTextChanged: page.filter = text
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Escape && text !== "") { text = ""; ev.accepted = true; }
                        else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Down) ev.accepted = true;
                    }
                    Label {
                        visible: field.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Name or keys"
                        size: Theme.tSub
                        color: Theme.textTertiary
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Find a shortcut"
                }
            }
        }
        SettingsRow {
            visible: KeyBinds.changed > 0
            label: "Your shortcuts"
            detail: KeyBinds.changed === 1 ? "One is yours; the rest are as they came" : KeyBinds.changed + " are yours; the rest are as they came"
            Button { height: Theme.sp(30); size: Theme.tSub; kind: "secondary"; text: "Reset all"; enabled: !KeyBinds.busy; onClicked: KeyBinds.resetAll() }
        }
        SettingsRow {
            visible: KeyBinds.error !== ""
            label: KeyBinds.error
        }
    }

    SettingsGroup {
        visible: KeyBinds.replaced !== ""
        title: "Replaced by your own config"
        Repeater {
            model: KeyBinds.replaced ? KeyBinds.replaced.split("\n") : []
            SettingsRow {
                required property var modelData
                readonly property var parts: String(modelData).replace(/^[^:]*:\s*/, "").split(/\s*←\s*replaced by\s*/)
                readonly property string was: String(parts[0] || "").replace(/^\[[^\]]*\]\s*/, "")
                readonly property string now: String(parts[1] || "").replace(/^\[[^\]]*\]\s*/, "")
                label: now ? now + " · was “" + was + "”" : was
                detail: page.chordText(String(modelData).replace(/:.*$/, ""))
            }
        }
    }

    Label {
        visible: KeyBinds.loaded && page.groups.length === 0 && page.filter.trim() !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: "No shortcut matches “" + page.filter.trim() + "”"
        size: Theme.tSub
        color: Theme.textTertiary
    }

    Repeater {
        model: page.groups
        SettingsGroup {
            id: grp
            required property var modelData
            title: modelData.group
            Repeater {
                model: grp.modelData.items
                SettingsRow {
                    id: r
                    required property var modelData
                    readonly property bool on: KeyBinds.editing === modelData.aid
                    label: modelData.text
                    detail: page.rowDetail(modelData)
                    Repeater {
                        model: r.on ? (KeyBinds.pending ? KC.caps(KeyBinds.pending.keys) : []) : KC.caps(r.modelData.keys)
                        KeyCap { required property var modelData; text: modelData }
                    }
                    Label {
                        visible: r.on && !KeyBinds.pending
                        text: "…"
                        size: Theme.tBody
                        color: Theme.textTertiary
                    }
                    Loader {
                        active: r.on
                        visible: active
                        sourceComponent: RowLayout {
                            spacing: Theme.s1
                            Button { height: Theme.sp(30); size: Theme.tSub; primary: true; enabled: KeyBinds.canSave; text: KeyBinds.clash && KeyBinds.clash.kind === "kuwai" ? "Replace" : "Save"; onClicked: page.save() }
                            Button { visible: !!r.modelData.keys && r.modelData.text !== "Lock"; height: Theme.sp(30); size: Theme.tSub; kind: "quiet"; text: "None"; onClicked: page.none() }
                            Button { height: Theme.sp(30); size: Theme.tSub; kind: "quiet"; text: "Cancel"; onClicked: page.stop(true) }
                        }
                    }
                    Loader {
                        active: !r.modelData.fixed
                        visible: active && !r.on
                        sourceComponent: RowLayout {
                            spacing: Theme.s1
                            Button {
                                id: change
                                height: Theme.sp(30); size: Theme.tSub; kind: "secondary"
                                text: r.modelData.keys ? "Change" : "Set"
                                enabled: !KeyBinds.busy
                                onClicked: page.edit(r.modelData, change)
                            }
                            Loader {
                                active: !!r.modelData.custom
                                visible: active
                                sourceComponent: Button {
                                    height: Theme.sp(30); size: Theme.tSub; kind: "quiet"
                                    text: "Default"
                                    enabled: !KeyBinds.busy
                                    onClicked: KeyBinds.reset(r.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
