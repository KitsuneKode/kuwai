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
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

FocusScope {
    id: picker
    focus: true
    implicitWidth: 980
    // Exactly three rows of cards between the header and the key hints.
    implicitHeight: 66 + 3 * (Math.round(Math.floor((980 - 32 - 330) / 4) * 0.5625) + 40) + 40

    property string mode: Island.themeMode || "themes"      // themes | wallpapers | live
    readonly property var modes: ["themes", "wallpapers", "live"]
    // Live wallpapers (bin/rice-wall json), with "Off" first: back to the still one.
    property var live: []
    readonly property var liveItems: [{ name: "Off", path: "", thumb: "", off: true, current: !live.some(x => x.current) }].concat(live)
    Process {
        id: liveLister
        running: picker.mode === "live"
        command: [Paths.bin + "/rice-wall", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { picker.live = JSON.parse(text); } catch (e) {}
                if (picker.mode === "live") picker.current = Math.max(0, picker.items.findIndex(x => x.current));
            }
        }
    }
    property var info: ({ current: "", themes: [], wallpapers: [] })
    property bool loading: true
    readonly property string bin: Paths.bin + "/rice-themes"
    readonly property var favs: Settings.favoriteThemes || []
    readonly property var items: mode === "live" ? liveItems
        : mode === "themes"
        ? info.themes.slice().sort((a, b) => (favs.includes(b.name) - favs.includes(a.name)) || a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
        : info.wallpapers
    property int current: 0
    property string colorMode: (info.modes || ["theme", "auto", "dark", "light"])[info.mode || 0]
    function setColorMode(id) {
        if (id === colorMode) return;
        info = Object.assign({}, info, { mode: ["theme", "auto", "dark", "light"].indexOf(id) });
        Quickshell.execDetached([bin, "colormode", id]);
        relist.restart();
    }
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
        if (mode === "live") {
            Quickshell.execDetached(it.off ? [Paths.bin + "/rice-wall", "off"] : [Paths.bin + "/rice-wall", "play", it.path]);
            relive.restart();
            return;
        }
        if (mode === "themes") Quickshell.execDetached([bin, "theme", it.name]);
        else Quickshell.execDetached([bin, "wallpaper", it.path]);
        relist.restart();
    }
    Timer { id: relist; interval: 2500; onTriggered: lister.running = true }
    Timer { id: relive; interval: 600; onTriggered: { liveLister.running = false; liveLister.running = true; } }
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
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) mode = modes[(modes.indexOf(mode) + (k === Qt.Key_Backtab ? 2 : 1)) % 3];
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
            options: [{ id: "themes", label: "Themes" }, { id: "wallpapers", label: "Wallpapers" }, { id: "live", label: "Live" }]
            current: picker.mode
            onPicked: id => picker.mode = id
        }
        Label {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: picker.mode === "live" ? "Plays behind your windows; pauses when they cover it" : picker.loading ? "Reading themes…" : (picker.info.current || "").replace(/-/g, " ")
            size: 13; weight: Theme.wMedium; color: Theme.textSecondary
        }
    }

    // The one you're on, large: the wallpaper as it will look, its name, the
    // theme's colours, and how to apply it.
    Item {
        id: preview
        anchors { right: parent.right; rightMargin: 22; top: parent.top; topMargin: 66 }
        width: 310
        readonly property var it: picker.items[picker.current] || null
        ClippingRectangle {
            id: big
            width: parent.width; height: Math.round(width * 0.5625)
            radius: 16
            color: preview.it && preview.it.bg ? preview.it.bg : Theme.pill
            Image {
                id: bigImg
                anchors.fill: parent
                source: preview.it ? "file://" + (preview.it.thumb || preview.it.path || "") : ""
                sourceSize: Qt.size(620, 349)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // A quick crossfade as the selection moves (not a slide: you're comparing).
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            // Live: the selected one plays here, muted (the panel's only decoder;
            // the cards are stills). A short wait so arrowing past doesn't decode each.
            Loader {
                anchors.fill: parent
                active: picker.mode === "live" && !!preview.it && !!preview.it.path && previewDwell.ready
                sourceComponent: Item {
                    VideoOutput { id: pv; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                    MediaPlayer {
                        source: "file://" + preview.it.path
                        videoOutput: pv
                        audioOutput: AudioOutput { muted: true }
                        loops: MediaPlayer.Infinite
                        Component.onCompleted: play()
                    }
                }
            }
            Timer { id: previewDwell; property bool ready: false; interval: 250; onTriggered: ready = true }
            Connections { target: picker; function onCurrentChanged() { previewDwell.ready = false; previewDwell.restart(); } function onModeChanged() { previewDwell.ready = false; previewDwell.restart(); } }
            Text {
                visible: !!preview.it && !!preview.it.off
                anchors.centerIn: parent
                text: "\u{f0e09}  Still wallpaper"
                font.family: Theme.fontGlyph; font.pixelSize: 15
                color: Theme.textSecondary
            }
        }
        Column {
            anchors { top: big.bottom; topMargin: 14; left: parent.left; right: parent.right }
            spacing: 6
            Label { width: parent.width; elide: Text.ElideRight; text: preview.it ? preview.it.name.replace(/-/g, " ") : ""; size: 17; weight: Theme.wSemibold }
            // The palette, as one strip: the theme's own colours (its terminal
            // palette), or the wallpaper's wallbash colours.
            Item {
                width: parent.width; height: 34
                visible: !!(preview.it && preview.it.palette && preview.it.palette.length)
                ClippingRectangle {
                    y: 4; width: parent.width; height: 14; radius: 7
                    color: "transparent"
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: preview.it && preview.it.palette ? preview.it.palette : []
                            Rectangle {
                                required property var modelData
                                width: parent.width / (preview.it.palette.length || 1); height: parent.height
                                color: modelData
                                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                            }
                        }
                    }
                }
                Label { y: 22; text: picker.mode === "themes" ? "Theme palette" : "Wallpaper colours"; size: 11; color: Theme.textTertiary }
            }
            Label { text: preview.it && preview.it.current ? "In use now" : picker.mode === "live" && preview.it && preview.it.off ? "Press ↵ to turn the live wallpaper off" : "Press ↵ or click to apply"; size: 12; color: Theme.textSecondary }
            Label { visible: picker.mode === "live"; width: parent.width; wrapMode: Text.Wrap; text: "Add your own: rice-wall add FILE.mp4 \"name\""; size: 11; color: Theme.textTertiary }
        }
    }

    // Where colours come from, for every app at once (HyDE's wallbash mode):
    // the theme's own palette, or the wallpaper's (as it is, darkened, lightened).
    Column {
        anchors { right: parent.right; rightMargin: 22; bottom: parent.bottom; bottomMargin: 14 }
        width: 310
        spacing: 8
        Label { text: "Colours"; size: 12; weight: Theme.wMedium; color: Theme.textSecondary }
        Segmented {
            width: parent.width
            options: [{ id: "theme", label: "Theme" }, { id: "auto", label: "Wallpaper" }, { id: "dark", label: "Dark" }, { id: "light", label: "Light" }]
            current: picker.colorMode
            onPicked: id => picker.setColorMode(id)
        }
    }

    GridView {
        id: grid
        x: 16; y: 66
        width: parent.width - 32 - 330
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
                Text {
                    visible: !!card.modelData.off
                    anchors.centerIn: parent
                    text: "\u{f0e09}"; font.family: Theme.fontGlyph; font.pixelSize: 22
                    color: Theme.textTertiary
                }
                Image {
                    anchors.fill: parent
                    visible: !card.modelData.off
                    source: card.modelData.thumb ? "file://" + card.modelData.thumb : ""
                    sourceSize: Qt.size(360, 202)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
                Row {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 5
                    visible: !!(card.modelData.palette && card.modelData.palette.length)
                    Repeater {
                        model: card.modelData.palette || []
                        Rectangle { required property var modelData; width: shot.width / card.modelData.palette.length; height: 5; color: modelData }
                    }
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
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 26
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
            model: [["← → ↑ ↓", "Choose"], ["↩", "Apply"], ["⇥", ({ themes: "Wallpapers", wallpapers: "Live", live: "Themes" })[picker.mode]], ["F", "Favourite"]]
            Row {
                required property var modelData
                spacing: 6
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }
                Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; size: 12; color: Theme.textTertiary }
            }
        }
    }
}
