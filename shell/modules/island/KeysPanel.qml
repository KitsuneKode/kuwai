// Every keyboard shortcut, grown out of the island (Super+/; replaces HyDE's
// rofi keybind hint). Read live from Hyprland (`hyprctl binds -j`), so it is
// always the truth: grouped by the category in each bind's description
// ("[Window Management] close focused window"), keys drawn as caps with the
// Mac glyphs (⌘ ⌃ ⇧ ⌥). Type to filter; ↑↓ scroll; Esc closes.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

FocusScope {
    id: keys
    focus: true
    implicitWidth: 760
    implicitHeight: 560

    property var binds: []
    property string query: ""
    Process {
        running: true
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let all = [];
                try { all = JSON.parse(text); } catch (e) { return; }
                const mods = m => [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]].filter(([b]) => m & b).map(([, n]) => n);
                const name = k => ({ Return: "↩", Escape: "Esc", space: "Space", slash: "/", comma: ",", period: ".", Print: "Print", BackSpace: "Backspace", Tab: "Tab",
                                     XF86AudioRaiseVolume: "Vol +", XF86AudioLowerVolume: "Vol −", XF86AudioMute: "Mute", XF86MonBrightnessUp: "Bright +", XF86MonBrightnessDown: "Bright −",
                                     XF86AudioPlay: "Play", XF86AudioNext: "Next", XF86AudioPrev: "Prev", XF86AudioMicMute: "Mic" })[k] || (k.length === 1 ? k.toUpperCase() : k);
                keys.binds = all.filter(b => b.has_description && b.description).map(b => {
                    const m = b.description.match(/^\[([^\]]+)\]\s*(.*)$/);
                    const group = m ? m[1].split("|")[0] : "Other";
                    const sub = m && m[1].includes("|") ? m[1].split("|").slice(1).join(" · ") : "";
                    return { group: group, sub: sub, text: m ? m[2] : b.description, keys: [...mods(b.modmask), name(b.key)] };
                });
            }
        }
    }

    readonly property var rows: {
        const q = query.trim().toLowerCase();
        const hits = binds.filter(b => !q || (b.text + " " + b.sub + " " + b.group + " " + b.keys.join(" ")).toLowerCase().includes(q));
        const out = [];
        let last = "";
        for (const b of hits.slice().sort((a, b) => a.group.localeCompare(b.group))) {
            if (b.group !== last) { out.push({ header: b.group }); last = b.group; }
            out.push(b);
        }
        return out;
    }

    Item {
        x: 18; y: 12
        width: parent.width - 36; height: 40
        Text { id: lens; anchors.verticalCenter: parent.verticalCenter; text: "\u{f030c}"; font.family: Theme.fontGlyph; font.pixelSize: 18; color: Theme.textTertiary }
        TextInput {
            id: field
            anchors { left: lens.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
            focus: true
            font.family: Theme.fontText
            font.pixelSize: 18
            color: Theme.textPrimary
            onTextChanged: keys.query = text
            Keys.onDownPressed: list.flick(0, -900)
            Keys.onUpPressed: list.flick(0, 900)
            Label { visible: !field.text; anchors.verticalCenter: parent.verticalCenter; text: "Search " + keys.binds.length + " shortcuts"; size: 18; color: Theme.textTertiary }
        }
    }
    Rectangle { x: 0; y: 63; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    ListView {
        id: list
        x: 10; y: 64
        width: parent.width - 20
        height: parent.height - y - 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: keys.rows
        delegate: Item {
            id: row
            required property var modelData
            width: list.width
            height: modelData.header ? 34 : 34
            Label {
                visible: !!row.modelData.header
                x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                text: row.modelData.header || ""
                size: 11; weight: Theme.wSemibold; color: Theme.accent; extraTracking: 0.4
            }
            Row {
                visible: !row.modelData.header
                x: 12; anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                width: 230
                Repeater {
                    model: row.modelData.keys || []
                    KeyCap { required property var modelData; text: modelData }
                }
            }
            Column {
                visible: !row.modelData.header
                x: 252; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 264
                Label { width: parent.width; elide: Text.ElideRight; text: (row.modelData.text || "").charAt(0).toUpperCase() + (row.modelData.text || "").slice(1); size: 13 }
                Label { visible: !!row.modelData.sub; width: parent.width; elide: Text.ElideRight; text: row.modelData.sub || ""; size: 11; color: Theme.textTertiary }
            }
        }
    }
}
