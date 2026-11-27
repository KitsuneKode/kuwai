// Themes and wallpapers, grown out of the island (Super+Shift+T, Super+Shift+W;
// replaces HyDE's rofi selectors). HyDE still does the switching (GTK, kitty,
// Hyprland, wallbash); kuwai follows on its own, because its accent is
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
import qs.modules.screensaver
import qs.components.ui as Ui

FocusScope {
    id: picker
    focus: true
    implicitWidth: Theme.panelXL
    // Exactly three rows of cards between the header and the key hints.
    implicitHeight: showPacks && packLoader.item
        ? packLoader.y + packLoader.item.implicitHeight + Theme.s4
        : Math.min(Theme.panelMaxH, 66 + 3 * (Math.round(Math.floor((Theme.panelXL - 32 - 330) / 4) * 0.5625) + 40)
            + 40 + (Theme.textScale > 1.5 ? 80 : Theme.textScale > 1.1 ? 30 : 0))

    property bool previewPlaying: false
    onCurrentChanged: previewPlaying = false
    property string mode: Island.themeMode || "themes"      // themes | wallpapers | live | saver
    property string wallScope: "all"
    property bool showPacks: false
    function togglePacks() {
        guide = false;
        showPacks = !showPacks;
        if (showPacks) WallpaperPacks.refresh();
    }
    Connections {
        target: WallpaperPacks
        function onInstalled() { if (picker.listed) relist.restart(); }
    }
    readonly property string activeScreen: Island.screen || Screens.focusedName || ""
    readonly property bool canTargetScreen: (info.monitors || []).some(m => m.name === activeScreen && m.identity)
    function isItemCurrent(it) {
        if (!it) return false;
        if (mode === "wallpapers" && info.screenWallpapers) {
            if (wallScope === "this") return it.path === info.screenWallpapers[activeScreen];
            const paths = Object.values(info.screenWallpapers);
            if (paths.length) return paths.every(path => path === it.path);
        }
        return !!it.current;
    }
    readonly property var modes: ["themes", "wallpapers", "live", "saver"]
    // Live wallpapers (bin/kuwai-wall json), with "Off" first: back to the still one.
    property var live: []
    readonly property var liveItems: [{ name: "Off", path: "", thumb: "", off: true, current: !live.some(x => x.current) }].concat(live)
    Process {
        id: liveLister
        running: picker.mode === "live"
        command: [Paths.bin + "/kuwai-wall", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { picker.live = JSON.parse(text); } catch (e) {}
                picker.liveListed = true;
                if (picker.mode === "live") picker.current = Math.max(0, picker.items.findIndex(x => x.current));
                if (picker.live.some(x => !x.thumb)) thumbsLater.restart();
            }
        }
    }
    property bool liveListed: false
    readonly property bool liveWaiting: mode === "live" && (!liveListed || live.some(x => !x.thumb))
    Timer { id: thumbsLater; interval: 1500; onTriggered: if (picker.mode === "live" && !liveLister.running) liveLister.running = true }
    // Screensavers: Dusk and Borealis (drawn live), every film in the folder (drop an .mp4
    // in, it's listed), your live wallpaper, or the still one. ↵ uses it,
    // P shows it now. Settings → Screensaver has when and after how long.
    readonly property string saverDir: Quickshell.env("HOME") + "/.local/share/kuwai-data/screensavers"
    property var clips: []
    Process {
        id: saverLister
        running: picker.mode === "saver"
        command: ["sh", "-c", 'cd "$1" 2>/dev/null && for f in *.mp4; do [ -e "$f" ] && echo "${f%.mp4}"; done', "saver", picker.saverDir]
        stdout: StdioCollector {
            onStreamFinished: {
                picker.clips = text.split("\n").filter(x => x);
                if (picker.mode === "saver") picker.current = Math.max(0, picker.items.findIndex(x => x.current));
            }
        }
    }
    function clipName(c) { return ({ "smoke-soft": "Smoke", "stars-lake": "Stars" })[c] || c.replace(/[-_]/g, " ").replace(/^./, x => x.toUpperCase()); }
    readonly property var saverItems: {
        const st = Settings.screensaverStyle || "still", clip = Settings.screensaverClip || "smoke-soft";
        const liveThumb = (live.find(x => x.current) || {}).thumb || "";
        // Dusk is drawn, so its picture ships with it (it looked in your films'
        // folder, where none was: a blank card).
        return [{ name: "Dusk", style: "dusk", thumb: Quickshell.shellDir + "/assets/screensaver/dusk.jpg", current: st === "dusk" },
                { name: "Borealis", style: "borealis", thumb: Quickshell.shellDir + "/assets/screensaver/borealis.jpg", current: st === "borealis" },
                { name: "Flow", style: "flow", thumb: Quickshell.shellDir + "/assets/screensaver/flow.jpg", current: st === "flow" }]
            .concat(clips.map(c => ({ name: "Night · " + clipName(c), style: "night", clip: c, thumb: saverDir + "/" + c + ".jpg", current: st === "night" && clip === c })))
            .concat([{ name: "Live wallpaper", style: "live", thumb: liveThumb, current: st === "live" },
                     { name: "Still wallpaper", style: "still", thumb: Hyde.wallpaper, current: st === "still" },
                     { name: "Photos", style: "photos", thumb: Quickshell.shellDir + "/assets/screensaver/photos.jpg", current: st === "photos" }]);
    }
    // What the preview pane can play for the one you're on: a live wallpaper's
    // loop, a screensaver's film, or a drawn scene (Dusk, Borealis) run small.
    // Space (or the button) plays and stops it. Until now only Live had a
    // preview, by pointer only; a screensaver could be seen only by P, which
    // closed the picker and showed whichever one was already set.
    readonly property var onIt: items[current] || null
    readonly property string previewPath: !onIt ? "" : mode === "live" ? (onIt.path || "")
        : mode !== "saver" ? "" : onIt.clip ? saverDir + "/" + onIt.clip + ".mp4"
        : onIt.style === "live" ? ((live.find(x => x.current) || {}).path || "") : ""
    readonly property string previewScene: mode === "saver" && onIt && (onIt.style === "dusk" || onIt.style === "borealis" || onIt.style === "flow") ? onIt.style : ""
    readonly property bool canPreview: previewPath !== "" || previewScene !== ""
    // P: use the one you're on, then show it full screen (it shows what is
    // set, so it is set first; it used to show the old one).
    function previewSaver() { if (mode === "saver") apply(current); Island.close(); saverGo.restart(); }
    Timer { id: saverGo; interval: 350; onTriggered: Quickshell.execDetached([Paths.bin + "/kuwai", "screensaver", "start"]) }

    // ── How to add your own (? or the header button): per tab, the steps,
    // the command (click: copied), the folder (Open), and what's worth adding.
    property bool guide: false
    onGuideChanged: {
        if (guide) { Island.innerBack = () => { picker.guide = false; }; Island.innerBackLabel = "Themes"; }
        else if (Island.innerBackLabel === "Themes") { Island.innerBack = null; Island.innerBackLabel = ""; }
    }
    Component.onDestruction: if (Island.innerBackLabel === "Themes") { Island.innerBack = null; Island.innerBackLabel = ""; }
    property string copied: ""
    Timer { id: copiedFor; interval: 1600; onTriggered: picker.copied = "" }
    function copyCmd(t) { Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "copy", t]); copied = t; copiedFor.restart(); }
    readonly property string home: Quickshell.env("HOME")
    readonly property var guides: ({
        themes: Hyde.present ? { title: "Add a theme",
            steps: ["Find a HyDE theme repository (search “hyde theme” on GitHub).", "Run the command with its name and URL.", "It appears here on the next open; ↵ applies it."],
            cmd: home + "/.local/lib/hyde/theme.patch.sh \"Theme-Name\" https://github.com/User/Repository",
            folder: home + "/.config/hyde/themes",
            worth: "One clear accent on near-black: the island keeps colour for state." } : { title: "Add a theme",
            steps: ["Install any kuwai theme git repository.", "Run kuwai-look install with the repository URL.", "It appears here on the next open; ↵ applies it."],
            cmd: "kuwai-look install https://github.com/User/kuwai-theme",
            folder: home + "/.local/share/kuwai-data/themes",
            worth: "One clear accent on near-black: the island keeps colour for state." },
        wallpapers: Hyde.present ? { title: "Add a wallpaper",
            steps: ["Pick an image at least 2560×1440 (PNG or JPG).", "Copy it into this theme's wallpapers folder.", "Reopen this tab; ↵ sets it, Colours can follow it."],
            cmd: "cp ~/Pictures/my-wallpaper.png \"" + home + "/.config/hyde/themes/" + (info.current || "THEME") + "/wallpapers/\"",
            folder: home + "/.config/hyde/themes/" + (info.current || "") + "/wallpapers",
            worth: "A calm, dark top edge: the island and its text sit there." } : { title: "Add a wallpaper",
            steps: ["Pick an image at least 2560×1440 (PNG or JPG).", "Drop it into ~/Pictures/wallpapers or run kuwai-look set-wallpaper.", "Reopen this tab; ↵ sets it and recolours the desktop."],
            cmd: "kuwai-look set-wallpaper ~/Pictures/my-wallpaper.png",
            folder: home + "/Pictures/wallpapers",
            worth: "A calm, dark top edge: the island and its text sit there." },
        live: { title: "Add a live wallpaper",
            steps: ["Any video works (MP4/WebM); slow and dark looks best.", "kuwai-wall makes it loop without a seam and sizes it for your screens.", "Wallpaper Engine videos: kuwai-wall import <workshop folder>."],
            cmd: "kuwai-wall add ~/Videos/clip.mp4 \"name\"",
            folder: home + "/Pictures/live-wallpapers",
            worth: "Slow motion, dark tones; it pauses when windows cover it." },
        saver: { title: "Add a screensaver",
            steps: ["Any video: smoke, stars, aurora, ink in water.", "kuwai saver plays it at half speed, forward then back (no seam).", "Pick it here as “Night · Name”; P shows it now."],
            cmd: "kuwai saver add ~/Videos/clip.mp4 name",
            folder: home + "/.local/share/kuwai-data/screensavers",
            worth: "Mostly black with slow movement: kind to OLED, never distracting." }
    })
    readonly property var guideNow: guides[mode] || guides.themes

    property var info: ({ current: "", themes: [], wallpapers: [] })
    property bool loading: true
    readonly property bool useLook: !Hyde.present
    readonly property string bin: Paths.bin + (useLook ? "/kuwai-look" : "/kuwai-themes")
    readonly property var favs: Settings.favoriteThemes || []
    readonly property var items: mode === "saver" ? saverItems
        : mode === "live" ? liveItems
        : mode === "themes"
        ? info.themes.slice().sort((a, b) => (favs.includes(b.name) - favs.includes(a.name)) || a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
        : info.wallpapers
    property int current: 0
    property string colorMode: (info.modes || ["theme", "auto", "dark", "light"])[info.mode || 0]
    function setColorMode(id) {
        if (id === colorMode) return;
        if (applicator.running) return;
        applyError = "";
        applicator.command = useLook ? [bin, "mode", id] : [bin, "colormode", id, "--wait"];
        applicator.running = true;
        relist.restart();
    }

    // Opening shows the last listing at once (kuwai-themes keeps it in
    // ~/.cache/kuwai/themes-list.json; this panel is destroyed on close, so it
    // used to start from nothing every time), then the fresh one replaces it.
    // Only the very first open, with no listing kept yet, shows the skeleton.
    // Read now (blockLoading), once the panel is built: an async read
    // finishing after a quick close could land in a destroyed panel.
    FileView {
        id: kept
        path: Quickshell.env("HOME") + "/.cache/kuwai/themes-list.json"
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        try { const t = !useLook ? kept.text() : ""; if (t && loading) took(JSON.parse(t)); } catch (e) {}
        Qt.callLater(() => picker.settled = true);
    }
    // Built: from here a change fades (the skeleton giving way to the cards);
    // an open that had the kept listing from the start shows it, no fade.
    property bool settled: false
    // The selection moved by hand: a fresh listing keeps it (by name), not
    // the one in use.
    property bool touched: false
    function took(listing) {
        const was = items[current];
        info = listing;
        loading = false;
        let i = touched && was ? items.findIndex(x => x.name === was.name) : -1;
        if (i < 0) i = items.findIndex(x => x.current);
        current = Math.max(0, i);
        Qt.callLater(() => grid.positionViewAtIndex(picker.current, GridView.Center));
    }
    Process {
        id: lister
        running: true
        command: [picker.bin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let listing = null;
                try { listing = JSON.parse(text); } catch (e) {}
                if (listing) picker.took(listing);
                else picker.loading = false;      // nothing to show: the empty state says so
            }
        }
    }
    // One sweep for every placeholder (Skeleton.phase), only while loading.
    property real sheen: 0
    NumberAnimation on sheen {
        running: (picker.loading || picker.liveWaiting) && picker.visible && !Theme.reduceMotion
        from: 0; to: 1
        duration: Theme.shimmerMs
        loops: Animation.Infinite
    }
    readonly property bool listed: mode === "themes" || mode === "wallpapers"     // what kuwai-themes lists
    onCanTargetScreenChanged: if (!canTargetScreen) wallScope = "all"
    onModeChanged: { showPacks = false; previewPlaying = false; current = Math.max(0, items.findIndex(x => x.current)); grid.positionViewAtIndex(current, GridView.Center); }

    function apply(i) {
        const it = items[i];
        if (!it) return;
        const nice = it.name.replace(/-/g, " ");
        if (applicator.running) { said("Still applying " + applyingName.replace(/-/g, " ") + "…"); return; }
        applyError = "";
        if (mode === "saver") {
            Settings.set("screensaverStyle", it.style);
            if (it.clip) Settings.set("screensaverClip", it.clip);
            said("Screensaver: " + nice);
            return;
        }
        if (mode === "live") {
            if (it.off) WallFx.liveOff();
            else WallFx.playLive(it.path);
            relive.restart();
            said(it.off ? "Live wallpaper off" : "Live wallpaper: " + nice);
            return;
        }
        applyingName = it.name;
        if (mode === "themes") {
            if (useLook) {
                applicator.environment = ({});
                applicator.command = [bin, "theme", it.name];
                applicator.running = true;
                return;
            }
            const name = it.name;
            WallFx.play(Hyde.config + "/themes/" + name + "/wall.set", () => Quickshell.execDetached(["env", "WALLPAPER_AWWW_TRANSITION_DEFAULT=none", bin, "theme", name]));
            return;
        }
        // A wallpaper: the shell plays the change (services/WallFx: the new
        // picture grows out of the island); awww's own transition is off.
        if (wallScope === "this" && !canTargetScreen) return;
        WallFx.playWallpaper(it.path, wallScope === "this" ? activeScreen : "");
        relist.restart();
    }
    // What an apply did, said where you are looking: which one is being
    // applied (and a turning mark on its card), that it landed, or why it
    // didn't. A screensaver or a live wallpaper used to change with no sign at
    // all; a theme said "Applying…" in small type and, on failure, "Couldn't
    // apply the selection" without the reason.
    property string applyError: ""
    property string applyingName: ""
    property string applyNote: ""
    function said(text) { applyNote = text; noteFor.restart(); }
    Timer { id: noteFor; interval: 2400; onTriggered: picker.applyNote = "" }
    Process {
        id: applicator
        stderr: StdioCollector { id: applyErr }
        onExited: (code, status) => {
            const nice = picker.applyingName.replace(/-/g, " ");
            if (code === 0) {
                picker.applyError = "";
                picker.said(nice ? nice + " applied" : "Colours updated");
                if (picker.useLook) { Theme.reloadLook(); Hyde.refresh(); }
            }
            else {
                const why = String(applyErr.text || "").split("\n").map(x => x.trim()).filter(x => x).pop() || "";
                picker.applyError = "Couldn't apply " + (nice || "colours") + (why ? ": " + why.slice(0, 120) : "") + " · ↵ tries again";
            }
            picker.applyingName = "";
            lister.running = true;
        }
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

    readonly property int cols: Theme.textScale > 1.5 ? 2 : 4
    Keys.onPressed: event => {
        const k = event.key, cols = picker.cols;
        if (showPacks) {
            if (k === Qt.Key_Escape) { togglePacks(); event.accepted = true; }
            return;
        }
        if ([Qt.Key_Right, Qt.Key_Left, Qt.Key_Down, Qt.Key_Up].indexOf(k) >= 0) touched = true;
        if (k === Qt.Key_Right) current = Math.min(items.length - 1, current + 1);
        else if (k === Qt.Key_Left) current = Math.max(0, current - 1);
        else if (k === Qt.Key_Down) current = Math.min(items.length - 1, current + cols);
        else if (k === Qt.Key_Up) current = Math.max(0, current - cols);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) apply(current);
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) mode = modes[(modes.indexOf(mode) + (k === Qt.Key_Backtab ? modes.length - 1 : 1)) % modes.length];
        else if (k === Qt.Key_P && mode === "saver") { previewSaver(); return; }
        else if (k === Qt.Key_Space && canPreview) { previewPlaying = !previewPlaying; event.accepted = true; return; }
        else if (k === Qt.Key_Question || (k === Qt.Key_Slash && (event.modifiers & Qt.ShiftModifier))) { guide = !guide; event.accepted = true; return; }
        else if (k === Qt.Key_Escape && guide) { guide = false; event.accepted = true; return; }
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
            options: [{ id: "themes", label: "Themes" }, { id: "wallpapers", label: "Wallpapers" }, { id: "live", label: "Live" }, { id: "saver", label: "Screensaver" }]
            current: picker.mode
            onPicked: id => picker.mode = id
        }
        Ui.Button {
            id: guideBtn
            visible: !picker.showPacks
            height: Theme.sp(30); size: Theme.tSub
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: picker.guide ? "Done" : "How to add"
            onClicked: picker.guide = !picker.guide
        }
        Ui.Button {
            visible: picker.mode === "wallpapers"
            height: Theme.sp(30); size: Theme.tSub
            anchors { right: picker.showPacks ? parent.right : guideBtn.left; rightMargin: picker.showPacks ? 0 : Theme.s2; verticalCenter: parent.verticalCenter }
            text: picker.showPacks ? "Back to wallpapers" : "Get more"
            onClicked: picker.togglePacks()
        }
        Label {
            visible: picker.mode !== "wallpapers"
            anchors { right: guideBtn.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: picker.mode === "saver" ? (Settings.screensaverWhen === "off" ? "Off · Settings → Screensaver"
                    : (Settings.screensaverWhen === "caffeine" ? "With Caffeine on" : "Before the lock") + " · after " + Idle.saverAfterText + " · P to see it")
                : picker.mode === "live" ? "Plays behind your windows; pauses when they cover it" : (picker.info.current || "").replace(/-/g, " ")
            size: Theme.tBody; weight: Theme.wMedium; color: Theme.textSecondary
        }
        // Loading: the theme's name, in its own shape.
        Skeleton {
            visible: picker.loading && picker.mode === "themes"
            anchors { right: guideBtn.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 120; height: 12
            phase: picker.sheen
        }
    }

    // The one you're on, large: the wallpaper as it will look, its name, the
    // theme's colours, and how to apply it.
    Item {
        id: preview
        visible: !picker.showPacks
        anchors { right: parent.right; rightMargin: 22; top: parent.top; topMargin: 66 }
        width: 310
        readonly property var it: picker.items[picker.current] || null
        ClippingRectangle {
            id: big
            width: parent.width; height: Math.round(width * (Theme.textScale > 1.5 ? 0.36 : 0.5625))
            radius: Theme.r3
            color: preview.it && preview.it.bg ? preview.it.bg : Theme.pill
            Image {
                id: bigImg
                anchors.fill: parent
                source: preview.it && (preview.it.thumb || (picker.mode !== "themes" && preview.it.path)) ? "file://" + (preview.it.thumb || preview.it.path) : ""
                sourceSize: Qt.size(620, 349)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // A quick crossfade as the selection moves (not a slide: you're comparing).
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
            }
            Column {
                visible: picker.mode === "themes" && !!preview.it && !preview.it.thumb
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Theme.s4 }
                spacing: Theme.s2
                Text {
                    visible: Theme.textScale <= 1.25
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f01da}"
                    font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphL
                    color: Theme.textSecondary
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Downloads on first use"
                    size: Theme.tSub
                    color: Theme.textSecondary
                }
            }
            // Live: the selected one plays here, muted (the panel's only decoder;
            // the cards are stills). A short wait so arrowing past doesn't decode each.
            Loader {
                anchors.fill: parent
                active: picker.visible && picker.previewPath !== "" && previewDwell.ready && picker.previewPlaying
                sourceComponent: Item {
                    VideoOutput { id: pv; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                    MediaPlayer {
                        source: "file://" + picker.previewPath
                        videoOutput: pv
                        audioOutput: AudioOutput { muted: true }
                        loops: MediaPlayer.Infinite
                        Component.onCompleted: play()
                        Component.onDestruction: stop()
                    }
                }
            }
            // A drawn screensaver (Dusk, Borealis), running small.
            Loader {
                anchors.fill: parent
                active: picker.visible && picker.previewScene !== "" && previewDwell.ready && picker.previewPlaying
                sourceComponent: picker.previewScene === "borealis" ? borealisPreview : picker.previewScene === "flow" ? flowPreview : duskPreview
            }
            Component { id: duskPreview; DuskScene { running: true } }
            Component { id: borealisPreview; BorealisScene { running: true } }
            Component { id: flowPreview; FlowScene { running: true } }
            Row {
                visible: picker.canPreview
                anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
                spacing: 6
                Ui.Button {
                    height: Theme.sp(30); size: Theme.tSub
                    visible: picker.mode === "saver"
                    text: "Full screen"
                    onClicked: picker.previewSaver()
                }
                Ui.Button {
                    height: Theme.sp(30); size: Theme.tSub
                    text: picker.previewPlaying ? "Stop preview" : "Preview"
                    onClicked: picker.previewPlaying = !picker.previewPlaying
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
        // Loading: the picture, the name and the palette strip, where they'll be.
        Item {
            id: previewSkeleton
            visible: picker.loading && picker.listed
            width: parent.width
            Skeleton { width: big.width; height: big.height; radius: big.radius; phase: picker.sheen }
            Skeleton { y: big.height + 14 + 3; width: 170; height: 16; phase: picker.sheen }
            Skeleton { y: big.height + 14 + 22 + 6 + 4; width: parent.width; height: 14; radius: 7; phase: picker.sheen }
        }
        Column {
            visible: !previewSkeleton.visible
            anchors { top: big.bottom; topMargin: 14; left: parent.left; right: parent.right }
            spacing: 6
            Label { width: parent.width; elide: Text.ElideRight; text: preview.it ? preview.it.name.replace(/-/g, " ") : ""; size: Theme.tTitle3; weight: Theme.wSemibold }
            // The palette, as one strip: the theme's own colours (its terminal
            // palette), or the wallpaper's wallbash colours.
            Item {
                width: parent.width; height: 22 + palCaption.implicitHeight
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
                Label { id: palCaption; y: 22; text: picker.mode === "themes" ? "Theme palette" : "Wallpaper colours"; size: Theme.tFootnote; color: Theme.textTertiary }
            }
            Row {
                id: applyLine
                readonly property bool busy: applicator.running
                readonly property string words: busy ? (picker.applyingName ? "Applying " + picker.applyingName.replace(/-/g, " ") + "…" : "Updating colours…") : picker.applyError !== "" ? picker.applyError : picker.applyNote
                visible: words !== ""
                spacing: 6
                Accessible.role: Accessible.StatusBar
                Accessible.name: words
                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: applyLine.busy ? "\u{f0772}" : picker.applyError !== "" ? "\u{f0026}" : "\u{f012c}"      // turning · alert · check
                    font.family: Theme.fontGlyph; font.pixelSize: Theme.tCallout
                    color: picker.applyError !== "" && !applyLine.busy ? Theme.orange : applyLine.busy ? Theme.textSecondary : Theme.green
                    RotationAnimation on rotation { running: applyLine.busy && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                    onVisibleChanged: rotation = 0
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, preview.width - 24)
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: applyLine.words
                    size: Theme.tSub
                    color: picker.applyError !== "" && !applyLine.busy ? Theme.orange : Theme.textSecondary
                }
            }
            Label { visible: !applyLine.visible; text: picker.isItemCurrent(preview.it) ? (picker.mode === "wallpapers" && picker.wallScope === "this" ? "In use on this screen" : "In use now") : picker.mode === "live" && preview.it && preview.it.off ? "Press ↵ to turn the live wallpaper off" : "Press ↵ or click to apply"; size: Theme.tSub; color: Theme.textSecondary }
            Label { visible: picker.mode === "live"; width: parent.width; wrapMode: Text.Wrap; text: "Add your own: kuwai-wall add FILE.mp4 \"name\" · guide: docs/manual/looks.md"; size: Theme.tFootnote; color: Theme.textTertiary }
            Label { visible: picker.mode === "saver"; width: parent.width; wrapMode: Text.Wrap; text: "Add your own: kuwai saver add FILE.mp4 · guide: docs/manual/looks.md"; size: Theme.tFootnote; color: Theme.textTertiary }
        }
    }

    // Where colours come from, for every app at once (HyDE's wallbash mode):
    // the theme's own palette, or the wallpaper's (as it is, darkened, lightened).
    Column {
        visible: !picker.showPacks && picker.listed
        anchors { right: parent.right; rightMargin: 22; bottom: parent.bottom; bottomMargin: 14 }
        width: 310
        spacing: Theme.s2
        Column {
            visible: picker.mode === "wallpapers" && picker.canTargetScreen
            width: parent.width
            spacing: Theme.s1
            Label {
                visible: Theme.textScale <= 1.5
                width: parent.width
                elide: Text.ElideRight
                text: "Apply to"
                size: Theme.tSub; weight: Theme.wMedium; color: Theme.textSecondary
            }
            Segmented {
                width: parent.width
                options: [{ id: "all", label: "All screens" }, { id: "this", label: "This screen" }]
                current: picker.wallScope
                onPicked: id => picker.wallScope = id
            }
        }
        Label { text: "Colours"; size: Theme.tSub; weight: Theme.wMedium; color: Theme.textSecondary }
        Segmented {
            width: parent.width
            options: [{ id: "theme", label: "Theme" }, { id: "auto", label: "Wallpaper" }, { id: "dark", label: "Dark" }, { id: "light", label: "Light" }]
            current: picker.colorMode
            onPicked: id => picker.setColorMode(id)
        }
    }

    // Loading (only the first open ever, or with no listing kept): cards in
    // the real ones' cells, so nothing moves when they arrive; the field
    // fades out as they come in. Gone (not hidden) once loaded: nothing of
    // it runs after.
    Item {
        id: cardsSkeleton
        x: grid.x; y: grid.y
        width: grid.width; height: grid.height
        clip: true
        opacity: (picker.loading && picker.listed) || (picker.mode === "live" && !picker.liveListed) ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { enabled: picker.settled; NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        Accessible.role: Accessible.Animation
        Accessible.name: picker.mode === "wallpapers" ? "Loading wallpapers" : picker.mode === "live" ? "Loading live wallpapers" : "Loading themes"
        Loader {
            active: cardsSkeleton.visible
            sourceComponent: Grid {
                columns: 4
                Repeater {
                    model: 4 * Math.ceil(grid.height / Math.max(1, grid.cellHeight))
                    Item {
                        width: grid.cellWidth; height: grid.cellHeight
                        Skeleton {
                            id: shotSk
                            x: 6; y: 6
                            width: parent.width - 12
                            height: Math.round(width * 0.5625)
                            radius: Theme.r2
                            phase: picker.sheen
                        }
                        Skeleton { x: 8; y: shotSk.y + shotSk.height + 8 + 3; width: Math.round(shotSk.width * 0.55); height: 10; phase: picker.sheen }
                    }
                }
            }
        }
    }
    // Empty: listed, and nothing there.
    Column {
        visible: !picker.showPacks && !picker.loading && picker.listed && picker.items.length === 0
        anchors.centerIn: grid
        width: grid.width - 40
        spacing: 6
        Label {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            // Themes and their wallpapers are HyDE's (kuwai-themes says when it isn't installed).
            text: picker.info.hyde === false ? "Themes and wallpapers come from HyDE, which isn't installed"
                : picker.mode === "themes" ? "No themes found" : picker.useLook ? "No wallpapers yet" : "This theme has no wallpapers of its own"
            size: Theme.tSub; weight: Theme.wSemibold; color: Theme.textSecondary
        }
        Label {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: picker.info.hyde === false ? "Live wallpapers and screensavers (their tabs) work without it." : "How to add (top right, or ?) shows where they go."
            size: Theme.tFootnote; color: Theme.textTertiary
        }
    }

    // More that way: the rows fade, and a thumb shows while it scrolls.

    ScrollFade { flickable: grid; active: !picker.showPacks }

    ScrollHint { flickable: grid; inside: true }

    GridView {
        id: grid
        visible: !picker.showPacks
        x: 16; y: 66
        width: parent.width - 32 - 330
        height: parent.height - y - 40
        cellWidth: Math.floor(width / picker.cols)
        cellHeight: Math.round(cellWidth * 0.5625) + Theme.sp(40)
        opacity: picker.loading && picker.listed ? 0 : 1
        Behavior on opacity { enabled: picker.settled; NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: picker.items
        cacheBuffer: 400

        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool on: index === picker.current
            readonly property bool isCurrent: picker.isItemCurrent(modelData)
            width: grid.cellWidth; height: grid.cellHeight

            ClippingRectangle {
                id: shot
                x: 6; y: 6
                width: parent.width - 12
                height: Math.round(width * 0.5625)
                radius: Theme.r2
                color: card.modelData.bg || Theme.pill
                Text {
                    visible: !!card.modelData.off
                    anchors.centerIn: parent
                    text: "\u{f0e09}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphL
                    color: Theme.textTertiary
                }
                Column {
                    visible: !card.modelData.off && picker.mode === "themes" && !card.modelData.thumb
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Theme.s2; verticalCenterOffset: -2 }
                    spacing: Theme.s1
                    Text {
                        visible: Theme.textScale <= 1.25
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\u{f01da}"
                        font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphS
                        color: Theme.textSecondary
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: "Downloads on first use"
                        size: Theme.tCaption
                        color: Theme.textSecondary
                    }
                }
                Skeleton {
                    anchors.fill: parent
                    radius: Theme.r2
                    phase: picker.sheen
                    visible: !card.modelData.off && (thumbImg.status === Image.Loading || (picker.mode === "live" && !card.modelData.thumb))
                }
                Image {
                    id: thumbImg
                    anchors.fill: parent
                    visible: !card.modelData.off && opacity > 0
                    source: card.modelData.thumb ? "file://" + card.modelData.thumb : ""
                    sourceSize: Qt.size(360, 202)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
                visible: applicator.running && picker.applyingName === card.modelData.name && !card.isCurrent
                anchors { right: shot.right; top: shot.top; margins: 8 }
                width: 22; height: 22; radius: 11
                color: Theme.chip
                Text {
                    id: spinGlyph
                    textFormat: Text.PlainText
                    anchors.centerIn: parent; text: "\u{f0772}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.tBody; color: Theme.textPrimary
                    // By id: `parent` went null while a closing panel tore the cards down (81 warnings a close).
                    RotationAnimation on rotation { running: spinGlyph.visible && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                }
            }
            Rectangle {
                visible: card.isCurrent
                anchors { right: shot.right; top: shot.top; margins: 8 }
                width: 22; height: 22; radius: 11
                color: Theme.accent
                Text { anchors.centerIn: parent; text: "\u{f012c}"; font.family: Theme.fontGlyph; font.pixelSize: 13; color: Theme.inkOnLight }
            }
            Row {
                anchors { left: shot.left; leftMargin: 2; top: shot.bottom; topMargin: 8 }
                width: shot.width
                spacing: 6
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (picker.mode === "themes" ? Theme.sp(30) : 0)
                    wrapMode: picker.mode === "wallpapers" ? Text.Wrap : Text.NoWrap
                    maximumLineCount: picker.mode === "wallpapers" ? 2 : 1
                    elide: Text.ElideRight
                    text: card.modelData.name.replace(/-/g, " ")
                    size: Theme.tSub; weight: card.on ? Theme.wMedium : Theme.wRegular
                    color: card.on ? Theme.textPrimary : Theme.textSecondary
                }
                Item {
                    visible: picker.mode === "themes"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: picker.favs.includes(card.modelData.name) ? "\u{f04ce}" : "\u{f04d2}"
                        font.family: Theme.fontGlyph; font.pixelSize: Theme.tSub
                        color: picker.favs.includes(card.modelData.name) ? Theme.yellow : (card.on ? Theme.textTertiary : "transparent")
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.toggleFav(card.index)
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "Favourite " + card.modelData.name.replace(/-/g, " ")
                        Accessible.checkable: true
                        Accessible.checked: picker.favs.includes(card.modelData.name)
                        Accessible.onPressAction: picker.toggleFav(card.index)
                        Accessible.onToggleAction: picker.toggleFav(card.index)
                    }
                }
            }
            MouseArea {
                id: cardArea
                anchors.fill: shot
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: { picker.touched = true; picker.current = card.index; }
                onClicked: picker.apply(card.index)
                Accessible.role: Accessible.ListItem
                Accessible.name: card.modelData.name.replace(/-/g, " ")
                Accessible.selected: card.on
                Accessible.onPressAction: picker.apply(card.index)
            }
        }
    }

    Row {
        id: themeHints
        anchors { left: parent.left; leftMargin: 22; bottom: parent.bottom; bottomMargin: 14 }
        visible: !picker.showPacks && picker.items.length > 0 && x + width <= preview.x - Theme.s2
        spacing: 14
        Repeater {
            // The keys that work on this tab. (It said "⇥ Themes" on Live, where
            // Tab goes to Screensaver; nothing after ⇥ on Screensaver; and
            // "F Favourite" on every tab, though only themes have favourites.)
            model: [["← → ↑ ↓", "Choose"], ["↵", picker.mode === "saver" ? "Use" : "Apply"],
                    ["Tab", ({ themes: "Wallpapers", wallpapers: "Live", live: "Screensaver", saver: "Themes" })[picker.mode]]]
                .concat(picker.canPreview ? [["space", picker.previewPlaying ? "Stop preview" : "Preview"]] : [])
                .concat(picker.mode === "saver" ? [["P", "Use and show now"]] : [])
                .concat(picker.mode === "themes" ? [["F", "Favourite"]] : [])
            Row {
                required property var modelData
                spacing: 6
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }
                Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; size: Theme.tFootnote; color: Theme.textTertiary }
            }
        }
    }

    Loader {
        id: packLoader
        anchors { fill: parent; leftMargin: Theme.s4; rightMargin: Theme.s4; topMargin: head.y + head.height + Theme.s3 }
        active: picker.showPacks
        sourceComponent: WallpaperPacksView {
            packs: WallpaperPacks.catalog
            state: WallpaperPacks.catalogState
            activePack: WallpaperPacks.activePack
            failedPack: WallpaperPacks.failedPack
            done: WallpaperPacks.done
            total: WallpaperPacks.total
            onDownload: pack => WallpaperPacks.download(pack)
            onRefresh: WallpaperPacks.refresh()
        }
    }

    // ── The guide sheet, over the preview column ─────────────────────────
    Rectangle {
        id: guideSheet
        x: preview.x - 8; y: 58
        width: preview.width + 16
        height: Math.min(parent.height - y - 14, gcol.implicitHeight + 32)
        radius: Theme.r3
        color: Qt.rgba(0.07, 0.07, 0.08, 0.98)
        border.width: 1; border.color: Theme.edge(1)
        z: 10
        visible: opacity > 0.01
        opacity: picker.guide ? 1 : 0
        transform: Translate { y: picker.guide || Theme.reduceMotion ? 0 : 8; Behavior on y { NumberAnimation { duration: picker.guide ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } } }
        Behavior on opacity { NumberAnimation { duration: picker.guide ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        MouseArea { anchors.fill: parent }   // keeps clicks off the grid behind

        Column {
            id: gcol
            x: 16; y: 16
            width: parent.width - 32
            spacing: 12
            Label { text: picker.guideNow.title; size: Theme.tTitle3; weight: Theme.wSemibold }
            Repeater {
                model: picker.guideNow.steps
                Row {
                    required property var modelData
                    required property int index
                    width: gcol.width
                    spacing: 10
                    Rectangle {
                        width: 20; height: 20; radius: 10
                        color: Theme.wash(2)
                        Label { anchors.centerIn: parent; text: String(index + 1); size: Theme.tCaption; weight: Theme.wSemibold; color: Theme.textSecondary }
                    }
                    Label { width: gcol.width - 30; wrapMode: Text.Wrap; text: modelData; size: Theme.tBody; color: Theme.textPrimary; lineHeight: 1.3 }
                }
            }
            // The command: click to copy.
            Rectangle {
                width: gcol.width
                height: cmdText.implicitHeight + 20
                radius: Theme.r2
                color: cmdArea.containsMouse ? Theme.tileHover : Theme.tileRest
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                Text {
                    textFormat: Text.PlainText
                    id: cmdText
                    x: 12; y: 10
                    width: parent.width - 24
                    wrapMode: Text.WrapAnywhere
                    text: picker.guideNow.cmd
                    font.family: "monospace"; font.pixelSize: Theme.tSub
                    color: Theme.textPrimary
                }
                MouseArea { id: cmdArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: picker.copyCmd(picker.guideNow.cmd) }
                Accessible.role: Accessible.Button
                Accessible.name: picker.copied === picker.guideNow.cmd ? "Copied" : "Copy the command"
                Accessible.description: picker.guideNow.cmd
                Accessible.onPressAction: picker.copyCmd(picker.guideNow.cmd)
            }
            Label {
                text: picker.copied === picker.guideNow.cmd ? "Copied: paste it in a terminal" : "Click the command to copy it"
                size: Theme.tFootnote
                color: picker.copied === picker.guideNow.cmd ? Theme.green : Theme.textTertiary
            }
            Label { width: gcol.width; wrapMode: Text.Wrap; text: picker.guideNow.worth; size: Theme.tSub; color: Theme.textSecondary }
            Row {
                spacing: 8
                Ui.Button { height: Theme.sp(30); size: Theme.tSub; text: "Open folder"; onClicked: Apps.open(picker.guideNow.folder) }
                Ui.Button { height: Theme.sp(30); size: Theme.tSub; text: "Full guide"; onClicked: Apps.open(Paths.root + "/docs/manual/looks.md") }
            }
        }
    }
}
