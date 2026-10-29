// Themes and wallpapers, grown out of the island (Super+Shift+T, Super+Shift+W;
// replaces HyDE's rofi selectors). HyDE still does the switching (GTK, kitty,
// Hyprland, wallbash); the rice follows on its own, because its accent is
// read from the wallpaper's palette. Favourites (★, or F) sort first.
//
//   Themes   Wallpapers                                   Abyssal Wave
//   ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
//   │ image │ │ image │ │ image │ │ image │      ← ↑ → ↓ choose, ↵ apply,
//   └───────┘ └───────┘ └───────┘ └───────┘        Tab switch, F favourite
//   ● Dracula ★ ● Nord   …
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

FocusScope {
    id: picker
    focus: true
    implicitWidth: 780
    // Exactly three rows of cards between the header and the key hints.
    implicitHeight: 66 + 3 * (Math.round(Math.floor((780 - 32) / 4) * 0.5625) + 40) + 40

    property string mode: Island.themeMode || "themes"      // themes | wallpapers
    property var info: ({ current: "", themes: [], wallpapers: [] })
    property bool loading: true
    readonly property string bin: Quickshell.env("HOME") + "/Projects/rice/bin/rice-themes"
    readonly property var favs: Settings.favoriteThemes || []
    readonly property var items: mode === "themes"
        ? info.themes.slice().sort((a, b) => (favs.includes(b.name) - favs.includes(a.name)))
        : info.wallpapers
    property int current: 0
    property string applied: ""        // what was just applied (shown until the listing catches up)

    Process {
        id: lister
        running: true
        command: [picker.bin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { picker.info = JSON.parse(text); } catch (e) {}
                picker.loading = false;
                const i = picker.items.findIndex(x => x.current);
                picker.current = Math.max(0, i);
                grid.positionViewAtIndex(picker.current, GridView.Center);
            }
        }
    }
    onModeChanged: { current = Math.max(0, items.findIndex(x => x.current)); grid.positionViewAtIndex(current, GridView.Center); }

    function apply(i) {
        const it = items[i];
        if (!it) return;
        applied = it.name;
        if (mode === "themes") Quickshell.execDetached([bin, "theme", it.name]);
        else Quickshell.execDetached([bin, "wallpaper", it.path]);
        relist.restart();
    }
    Timer { id: relist; interval: 2500; onTriggered: lister.running = true }
    function toggleFav(i) {
        const it = items[i];
        if (!it || mode !== "themes") return;
        const f = favs.slice();
        const k = f.indexOf(it.name);
        if (k >= 0) f.splice(k, 1); else f.push(it.name);
        Settings.set("favoriteThemes", f);
    }

    Keys.onPressed: event => {
        const k = event.key, cols = 4;
        if (k === Qt.Key_Right) current = Math.min(items.length - 1, current + 1);
        else if (k === Qt.Key_Left) current = Math.max(0, current - 1);
        else if (k === Qt.Key_Down) current = Math.min(items.length - 1, current + cols);
        else if (k === Qt.Key_Up) current = Math.max(0, current - cols);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) apply(current);
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) mode = mode === "themes" ? "wallpapers" : "themes";
        else if (k === Qt.Key_F) toggleFav(current);
        else return;
        grid.positionViewAtIndex(current, GridView.Contain);
        event.accepted = true;
    }

    Item {
        id: head
        x: 22; y: 18
        width: parent.width - 44; height: 36
        Segmented {
            anchors.verticalCenter: parent.verticalCenter
            options: [{ id: "themes", label: "Themes" }, { id: "wallpapers", label: "Wallpapers" }]
            current: picker.mode
            onPicked: id => picker.mode = id
        }
        Label {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: picker.loading ? "Reading themes…" : (picker.info.current || "").replace(/-/g, " ")
            size: 13; weight: Theme.wMedium; color: Theme.textSecondary
        }
    }

    GridView {
        id: grid
        x: 16; y: 66
        width: parent.width - 32
        height: parent.height - y - 40
        cellWidth: Math.floor(width / 4)
        cellHeight: Math.round(cellWidth * 0.5625) + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: picker.items
        cacheBuffer: 400

        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool on: index === picker.current
            readonly property bool isCurrent: modelData.current || picker.applied === modelData.name
            width: grid.cellWidth; height: grid.cellHeight

            ClippingRectangle {
                id: shot
                x: 6; y: 6
                width: parent.width - 12
                height: Math.round(width * 0.5625)
                radius: 12
                color: card.modelData.bg || Theme.pill
                Image {
                    anchors.fill: parent
                    source: "file://" + card.modelData.thumb
                    sourceSize: Qt.size(360, 202)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
                scale: cardArea.pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            }
            // Selection ring (keyboard / pointer) and the current one's check.
            Rectangle {
                x: shot.x - 3; y: shot.y - 3
                width: shot.width + 6; height: shot.height + 6
                radius: 15
                color: "transparent"
                border.width: card.on ? 2 : 0
                border.color: Theme.accent
            }
            Rectangle {
                visible: card.isCurrent
                anchors { right: shot.right; top: shot.top; margins: 8 }
                width: 22; height: 22; radius: 11
                color: Theme.accent
                Text { anchors.centerIn: parent; text: "\u{f012c}"; font.family: Theme.fontGlyph; font.pixelSize: 13; color: "#111114" }
            }
            Row {
                anchors { left: shot.left; leftMargin: 2; top: shot.bottom; topMargin: 8 }
                width: shot.width
                spacing: 6
                Rectangle { visible: !!card.modelData.accent; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: card.modelData.accent || "transparent" }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    elide: Text.ElideRight
                    text: card.modelData.name.replace(/-/g, " ")
                    size: 12; weight: card.on ? Theme.wMedium : Theme.wRegular
                    color: card.on ? Theme.textPrimary : Theme.textSecondary
                }
                Text {
                    visible: picker.mode === "themes"
                    anchors.verticalCenter: parent.verticalCenter
                    text: picker.favs.includes(card.modelData.name) ? "\u{f04ce}" : "\u{f04d2}"
                    font.family: Theme.fontGlyph; font.pixelSize: 13
                    color: picker.favs.includes(card.modelData.name) ? Theme.yellow : (card.on ? Theme.textTertiary : "transparent")
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: picker.toggleFav(card.index) }
                }
            }
            MouseArea {
                id: cardArea
                anchors.fill: shot
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: picker.current = card.index
                onClicked: picker.apply(card.index)
            }
        }
    }

    Row {
        anchors { left: parent.left; leftMargin: 22; bottom: parent.bottom; bottomMargin: 14 }
        spacing: 14
        Repeater {
            model: [["← → ↑ ↓", "Choose"], ["↩", "Apply"], ["⇥", picker.mode === "themes" ? "Wallpapers" : "Themes"], ["F", "Favourite"]]
            Row {
                required property var modelData
                spacing: 6
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }
                Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; size: 12; color: Theme.textTertiary }
            }
        }
    }
}
