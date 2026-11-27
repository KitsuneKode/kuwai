// Settings, grown out of the island (Super+, or the launcher's "Settings"):
// a sidebar of sections and grouped rows, like System Settings. Every row is
// a real setting (config/Settings, ~/.config/kuwai/settings.json); changes
// apply at once, nothing to save. Keys: ↑↓ section, type (or / or Ctrl+F)
// to search every row of every page, Esc clears the search, then closes.
//
//   ▣ Bar & Island     Bar & Island
//   ▣ Clock & Date     ┌──────────────────────────────────────────┐
//   ▣ Notifications    │ Top bar              [ Waybar | Island ] │
//   ▣ Motion           │ Workspaces at rest                  (●) │
//   ▣ About            └──────────────────────────────────────────┘
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui
import qs.services

FocusScope {
    id: settings
    focus: true

    implicitWidth: Theme.panelL
    implicitHeight: 520

    readonly property string kuwai: Paths.bin + "/kuwai"
    readonly property var sections: SettingsIndex.sections   // services/SettingsIndex (the launcher searches it too)
    property int current: 0
    property alias searchText: search.text       // for the screenshot preview (TestHook)

    // ── Search ── every row of every page (SettingsIndex.find): the sidebar
    // lists what matches; ↑↓ and Enter (or a click) go there, the page
    // scrolls to the row and it lights once. The search stays until cleared,
    // so the next result is one key away.
    readonly property string query: search.text.trim()
    readonly property var results: query ? SettingsIndex.find(query, 14) : []
    property int pick: 0
    property string target: ""            // the row the search points at
    property string targetGroup: ""       // and its group (Lock is in On power and On battery)
    onResultsChanged: { pick = 0; if (results.length) show(0, false); else target = ""; }
    onQueryChanged: if (!query) { target = ""; markLater.restart(); }
    property bool goPending: false
    function show(i, go) {
        const r = results[i];
        if (!r) return;
        pick = i;
        target = r.row ? r.row.label : "";
        targetGroup = r.row ? r.row.group : "";
        goPending = go;
        sideFlick.revealAt(i * (Theme.sp(44) + 2), Theme.sp(44));
        const si = sections.findIndex(x => x.id === r.section.id);
        if (si >= 0 && si !== current) current = si;     // onCurrentChanged marks once the page is in
        else markLater.restart();
    }
    // Once the page is built and laid out (a frame or two after it loads).
    Timer { id: markLater; interval: 32; onTriggered: settings.markFound() }
    // The page's rows: the target one found (a wash), scrolled to, pulsed when gone to.
    function markFound() {
        const go = goPending;
        goPending = false;
        if (!page.item) return;
        let hit = null;
        const walk = (it, group) => {
            for (const c of it.children) {
                const g = c.hasOwnProperty("title") && typeof c.title === "string" ? c.title : group;
                if (c.hasOwnProperty("found") && c.hasOwnProperty("detail")) {
                    const on = settings.target !== "" && c.label === settings.target
                        && (settings.targetGroup === "" || g === settings.targetGroup);
                    c.found = on;
                    if (on && !hit) hit = c;
                }
                walk(c, g);
            }
        };
        walk(page.item, "");
        if (!hit) return;
        const y = hit.mapToItem(page, 0, 0).y;
        const to = Math.max(0, Math.min(pageFlick.contentHeight - pageFlick.height, y - pageFlick.height * 0.3));
        if (Theme.reduceMotion) pageFlick.contentY = to;
        else { scrollTo.to = to; scrollTo.restart(); }
        if (go) hit.pulse();
    }
    NumberAnimation { id: scrollTo; target: pageFlick; property: "contentY"; duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    function goTo(page) {
        const i = sections.findIndex(x => x.id === page);
        if (i >= 0) current = i;
        if (page) Island.settingsPage = "";
    }
    Component.onCompleted: goTo(Island.settingsPage)
    Connections { target: Island; function onSettingsPageChanged() { settings.goTo(Island.settingsPage); } }

    // ↑ ↓ sections · Tab / ⇧Tab the page's controls (Tab used to switch
    // sections, so no control was reachable without a mouse) · PgUp / PgDn
    // scroll the page · Esc back (IslandBar).
    Keys.onPressed: event => {
        // Typing anywhere in Settings searches (not Space: it presses the
        // focused control). / and Ctrl+F go to the field too.
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (!search.activeFocus && ((event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) || (event.text === "/" && !mods))) {
            search.forceActiveFocus(); search.selectAll(); event.accepted = true; return;
        }
        if (!search.activeFocus && !mods && event.text.length === 1 && event.text > " " && event.text !== "\u007f") {
            search.forceActiveFocus(); search.insert(search.cursorPosition, event.text); event.accepted = true; return;
        }
        if (event.key === Qt.Key_Down) current = (current + 1) % sections.length;
        else if (event.key === Qt.Key_Up) current = (current + sections.length - 1) % sections.length;
        else if (event.key === Qt.Key_PageDown) pageFlick.contentY = Math.min(Math.max(0, pageFlick.contentHeight - pageFlick.height), pageFlick.contentY + pageFlick.height * 0.85);
        else if (event.key === Qt.Key_PageUp) pageFlick.contentY = Math.max(0, pageFlick.contentY - pageFlick.height * 0.85);
        else return;
        event.accepted = true;
    }
    onCurrentChanged: { scrollTo.stop(); pageFlick.contentY = 0; if (!query) sideFlick.reveal(current); markLater.restart(); }
    // A control reached with Tab scrolls into view.
    readonly property Item focusedItem: Window.activeFocusItem
    onFocusedItemChanged: {
        const f = focusedItem;
        if (!f || !page.item) return;
        let p = f; while (p && p !== page.item) p = p.parent;
        if (!p) return;
        const y = f.mapToItem(page, 0, 0).y;
        if (y < pageFlick.contentY + 8) pageFlick.contentY = Math.max(0, y - 16);
        else if (y + f.height > pageFlick.contentY + pageFlick.height - 8)
            pageFlick.contentY = Math.min(pageFlick.contentHeight - pageFlick.height, y + f.height - pageFlick.height + 16);
    }

    // ── Sidebar ──────────────────────────────────────────────────────────
    Rectangle {
        id: side
        width: Math.min(Theme.sp(212), Math.round(settings.width * 0.38))
        height: parent.height
        color: Theme.wash(0)
        // The search sits where the title was (System Settings): the panel
        // says "Settings" in its own header row (Accessible name below).
        Rectangle {
            id: searchBox
            x: 10; y: 12
            width: parent.width - 20
            height: Theme.sp(32)
            radius: 9
            color: Qt.rgba(1, 1, 1, search.activeFocus ? 0.10 : 0.06)
            border.width: 1
            border.color: search.activeFocus ? Theme.edge(3) : Theme.edge(0)
            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
            Behavior on border.color { ColorAnimation { duration: Theme.hoverMs } }
            Text {
                textFormat: Text.PlainText
                id: searchGlyph
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "\u{f0349}"                                   // magnify
                font.family: Theme.fontGlyph; font.pixelSize: 14
                color: Theme.textTertiary
            }
            TextInput {
                id: search
                anchors { left: searchGlyph.right; right: clearSearch.visible ? clearSearch.left : parent.right; leftMargin: 7; rightMargin: 8; verticalCenter: parent.verticalCenter }
                color: Theme.textPrimary
                selectionColor: Qt.alpha(Theme.blue, 0.5)
                selectedTextColor: Theme.textPrimary
                font.family: Theme.fontText
                font.pixelSize: Theme.sp(13)          // what you type grows with Text size, as its placeholder does
                font.variableAxes: ({ "opsz": Theme.opszFor(13), "wght": Theme.wRegular })
                font.letterSpacing: Theme.tracking(13, false)
                renderType: Text.NativeRendering
                cursorDelegate: SpringCaret {}
                clip: true
                // ↑↓ walk the results (or the pages, with nothing typed);
                // Enter goes; Esc clears first, a second Esc closes.
                Keys.onPressed: event => {
                    if (settings.query && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                        const n = settings.results.length;
                        if (n) settings.show((settings.pick + (event.key === Qt.Key_Down ? 1 : n - 1)) % n, false);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (settings.results.length) settings.show(settings.pick, true);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape && search.text !== "") {
                        search.text = "";
                        event.accepted = true;
                    }
                }
                Label {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search"
                    size: Theme.tBody
                    color: Theme.textTertiary
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search settings"
                Accessible.description: !settings.query ? "Type to find any setting"
                    : settings.results.length === 1 ? "1 result" : settings.results.length + " results"
            }
            Text {
                textFormat: Text.PlainText
                id: clearSearch
                visible: search.text !== ""
                anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                text: "\u{f0159}"                                   // close-circle
                font.family: Theme.fontGlyph; font.pixelSize: 14
                color: clearArea.containsMouse ? Theme.textSecondary : Theme.textTertiary
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                MouseArea {
                    id: clearArea
                    anchors { fill: parent; margins: -8 }
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { search.text = ""; search.forceActiveFocus(); }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Clear search"
                Accessible.onPressAction: { search.text = ""; search.forceActiveFocus(); }
            }
        }
        // Scrolls (13 sections didn't fit: About was out of reach), and keeps
        // the current one in view as ↑ ↓ move.
        Flickable {
          id: sideFlick
          x: 10; y: searchBox.y + searchBox.height + 10     // under the search, which grows with Text size (it was 54: the first row sat on it at 200 %)
          width: parent.width - 20
          height: parent.height - y - 10
          contentHeight: settings.query ? resCol.implicitHeight : sideCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          function reveal(i) { revealAt(i * 38, 36); }
          function revealAt(y, h) {
              if (y < contentY) contentY = y;
              else if (y + h > contentY + height) contentY = y + h - height;
          }
        Column {
            id: sideCol
            visible: !settings.query
            width: parent.width
            spacing: 2
            Accessible.role: Accessible.PageTabList
            Accessible.name: "Settings"

            Repeater {
                model: settings.sections
                Rectangle {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool on: settings.current === index
                    width: parent.width
                    height: Math.max(36, sideLabel.implicitHeight + 10)
                    radius: 9
                    color: on ? Theme.wash(2) : itemArea.containsMouse ? Theme.rowHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    Rectangle {
                        id: chip
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: 7
                        color: item.modelData.tint
                        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: item.modelData.glyph; font.family: Theme.fontGlyph; font.pixelSize: 14; color: "white" }
                    }
                    Label { id: sideLabel; anchors { left: chip.right; leftMargin: 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    wrapMode: Text.Wrap; maximumLineCount: 2
                    text: item.modelData.label; size: Theme.tBody; weight: item.on ? Theme.wMedium : Theme.wRegular }
                    MouseArea { id: itemArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settings.current = item.index }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: item.modelData.label
                    Accessible.selected: item.on
                    Accessible.onPressAction: settings.current = item.index
                }
            }
        }
        // What the search found: the row's name, and where it lives.
        Column {
            id: resCol
            visible: !!settings.query
            width: parent.width
            spacing: 2
            Accessible.role: Accessible.List
            Accessible.name: "Search results"
            Repeater {
                model: settings.results
                Rectangle {
                    id: res
                    required property var modelData
                    required property int index
                    readonly property bool on: settings.pick === index
                    width: parent.width
                    height: Math.max(Theme.sp(44), resText.implicitHeight + 12)
                    radius: 9
                    color: on ? Theme.wash(2) : resArea.containsMouse ? Theme.rowHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    Rectangle {
                        id: resChip
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 6
                        color: res.modelData.section.tint
                        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: res.modelData.section.glyph; font.family: Theme.fontGlyph; font.pixelSize: 13; color: "white" }
                    }
                    Column {
                        id: resText
                        anchors { left: resChip.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: res.modelData.row ? res.modelData.row.label : res.modelData.section.label
                            size: Theme.tBody; weight: res.on ? Theme.wMedium : Theme.wRegular
                        }
                        Label {
                            width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                            text: res.modelData.row ? res.modelData.section.label + (res.modelData.row.group ? " · " + res.modelData.row.group : "") : "Page"
                            size: Theme.tFootnote; color: Theme.textTertiary
                        }
                    }
                    MouseArea { id: resArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settings.show(res.index, true) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: (res.modelData.row ? res.modelData.row.label + ", in " : "") + res.modelData.section.label
                    Accessible.selected: res.on
                    Accessible.onPressAction: settings.show(res.index, true)
                }
            }
            // Nothing: say so, and what to try.
            Column {
                visible: settings.results.length === 0
                x: 12; topPadding: 14
                width: parent.width - 24
                spacing: 4
                Label { text: "No Results"; size: Theme.tBody; weight: Theme.wMedium; color: Theme.textSecondary }
                Label { width: parent.width; wrapMode: Text.Wrap; text: "Nothing in Settings matches “" + settings.query + "”. Try a shorter word."; size: Theme.tFootnote; color: Theme.textTertiary }
            }
        }
        }
        ScrollFade { flickable: sideFlick }
        ScrollHint { flickable: sideFlick; anchors { right: parent.right; top: sideFlick.top; bottom: sideFlick.bottom; rightMargin: 2 } }
    }
    Rectangle { x: side.width; width: 1; height: parent.height; color: Theme.wash(1) }

    // ── Content ──────────────────────────────────────────────────────────
    Item {
        id: content
        x: side.width + 1
        width: parent.width - x
        height: parent.height

        Label { id: heading; x: 28; y: 20; width: parent.width - 56; wrapMode: Text.Wrap; text: (settings.sections[settings.current] || {}).label || ""; size: Theme.tTitle2; weight: Theme.wSemibold }

        Label {
            id: saveStatus
            x: 28; y: heading.y + heading.height + 8
            width: parent.width - 56
            visible: text !== ""
            text: Settings.error || (Settings.pending ? "Saving changes…" : "")
            wrapMode: Text.Wrap
            size: Theme.tFootnote
            color: Settings.error ? Theme.red : Theme.textSecondary
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        Flickable {
            id: pageFlick
            x: 28; y: saveStatus.visible ? saveStatus.y + saveStatus.height + 12 : Math.max(62, heading.y + heading.height + 16)
            width: parent.width - 56
            height: parent.height - y - 16
            contentHeight: page.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: page
                width: parent.width
                sourceComponent: [barPage, clockPage, notifPage, assistantPage, motionPage, keyboardPage, shortcutsPage, pointerPage, displaysPage, islandRestPage, workspacesPage, powerPage, saverPage, timePage, clipboardPage, updatesPage, aboutPage][settings.current]
            }
        }
        ScrollFade { flickable: pageFlick }
        ScrollHint { flickable: pageFlick; anchors { right: parent.right; top: pageFlick.top; bottom: pageFlick.bottom; rightMargin: 10 } }
    }

    // ── Pages ────────────────────────────────────────────────────────────
    Component {
        id: barPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow {
                    label: "Top bar"; detail: "The island replaces Waybar; switch back any time"
                    Segmented {
                        options: [{ id: "waybar", label: "Waybar" }, { id: "island", label: "Island" }]
                        current: Settings.bar
                        onPicked: id => Quickshell.execDetached([settings.kuwai, "bar", id])
                    }
                }
                SettingsRow {
                    key: "islandStyle"
                    label: "Shape"; detail: "A floating island, or a notch hanging from the top edge"
                    Segmented {
                        options: [{ id: "floating", label: "Island" }, { id: "notch", label: "Notch" }]
                        current: Settings.islandStyle
                        onPicked: id => Settings.set("islandStyle", id)
                    }
                }
                SettingsRow {
                    key: "islandSplit"
                    label: "Separate pills"; detail: "Agents, T3 and system news float in small capsules either side of the island, and music steps into one while something else has it"
                    Toggle { on: Settings.islandSplit; onToggled: Settings.set("islandSplit", !Settings.islandSplit) }
                }
                SettingsRow {
                    key: "restWorkspaces"
                    label: "Workspaces at rest"; detail: "Capsules beside the clock"
                    Toggle { on: Settings.restWorkspaces; onToggled: Settings.set("restWorkspaces", !Settings.restWorkspaces) }
                }
                SettingsRow {
                    key: "restStatus"
                    label: "Signal and battery at rest"
                    Toggle { on: Settings.restStatus; onToggled: Settings.set("restStatus", !Settings.restStatus) }
                }
                SettingsRow {
                    key: "workspaceCount"
                    label: "Workspaces shown"; detail: "At least this many; more appear as they fill"
                    Segmented {
                        options: [3, 5, 7, 10].map(n => ({ id: String(n), label: String(n) }))
                        current: String(Settings.workspaceCount)
                        onPicked: id => Settings.set("workspaceCount", Number(id))
                    }
                }
                SettingsRow {
                    key: "limitAlerts"
                    label: "Limit alerts in the notch"; detail: "A moment when an agent's usage window nears its cap; a mark on the notch while one is used up, until it resets"
                    Toggle { on: Settings.limitAlerts; onToggled: Settings.set("limitAlerts", !Settings.limitAlerts) }
                }
                SettingsRow {
                    key: "limitThreshold"
                    visible: Settings.limitAlerts
                    label: "Alert at"; detail: "How much of a window is used before the notch says so"
                    Segmented {
                        options: [70, 80, 90].map(n => ({ id: String(n), label: n + "%" }))
                        current: String(Settings.limitThreshold)
                        onPicked: id => Settings.set("limitThreshold", Number(id))
                    }
                }
                SettingsRow {
                    key: "agentBudget"
                    label: "Daily agent budget"; detail: "An estimate at list prices from T3 Code's records; the Agents panel says when today passes it, each row says what its thread cost"
                    Segmented {
                        options: [0, 10, 25, 50, 100].map(n => ({ id: String(n), label: n ? "$" + n : "Off" }))
                        current: String(Settings.agentBudget)
                        onPicked: id => Settings.set("agentBudget", Number(id))
                    }
                }
            }
            SettingsGroup {
                title: "On hover"
                SettingsRow {
                    key: "restMedia"
                    label: "Music at rest"; detail: "Tiny art and bars beside the island while something plays"
                    Toggle { on: Settings.restMedia; onToggled: Settings.set("restMedia", !Settings.restMedia) }
                }
                SettingsRow {
                    key: "restWeather"
                    label: "Weather"; detail: "In the island, for " + (Settings.weatherLocation || ((Weather.place ? Weather.place : "where you are") + ", found from your connection")) + "  ·  kuwai set weatherLocation \"City\""
                    Toggle { on: Settings.restWeather; onToggled: Settings.set("restWeather", !Settings.restWeather) }
                }
                SettingsRow {
                    key: "hoverMedia"
                    label: "Now playing"; detail: "The media card under the clock"
                    Toggle { on: Settings.hoverMedia; onToggled: Settings.set("hoverMedia", !Settings.hoverMedia) }
                }
                SettingsRow {
                    key: "hoverView"
                    label: "Hover shows"; detail: Settings.hoverView === "full" ? "Everything at once: the app, workspaces, time, music, machine and status" : "A glance (app, time, music); click it for everything. Super+Alt+I opens everything too"
                    Segmented {
                        options: [{ id: "glance", label: "A glance" }, { id: "full", label: "Everything" }]
                        current: Settings.hoverView
                        onPicked: id => Settings.set("hoverView", id)
                    }
                }
                SettingsRow {
                    key: "hoverDelay"
                    label: "Hover delay"; detail: "How long the pointer rests before the island grows"
                    Segmented {
                        options: [0, 120, 220, 400].map(n => ({ id: String(n), label: n ? n + " ms" : "None" }))
                        current: String(Settings.hoverDelay)
                        onPicked: id => Settings.set("hoverDelay", Number(id))
                    }
                }
            }
        }
    }
    Component {
        id: clockPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow {
                    key: "clock24"
                    label: "24-hour time"
                    Toggle { on: Settings.clock24; onToggled: Settings.set("clock24", !Settings.clock24) }
                }
                SettingsRow {
                    key: "showSeconds"
                    label: "Show seconds"; detail: "The clock wakes every second instead of every five"
                    Toggle { on: Settings.showSeconds; onToggled: Settings.set("showSeconds", !Settings.showSeconds) }
                }
            }
        }
    }
    Component {
        id: notifPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow {
                    label: "Do Not Disturb"; detail: "Only critical alerts show"
                    Toggle { on: Notifs.dnd; onToggled: Notifs.toggleUserDnd() }
                }
                SettingsRow {
                    key: "notifSurface"
                    label: "Where they appear"
                    detail: Settings.notifSurface === "both" ? "In the island and as a toast" : "One place each: urgent, warnings and replies in the island; the rest as a toast; low ones only in the center"
                    Segmented {
                        options: [{ id: "one", label: "One place" }, { id: "both", label: "Both" }]
                        current: Settings.notifSurface
                        onPicked: id => Settings.set("notifSurface", id)
                    }
                }
                SettingsRow {
                    key: "notifFullscreen"
                    label: "In fullscreen"
                    detail: Settings.notifFullscreen === "off" ? "Nothing interrupts a fullscreen app; it all waits in the center"
                          : Settings.notifFullscreen === "critical" ? "Only critical ones grow the notch over the game or film"
                          : "The notch grows for critical ones, warnings and people you can reply to; the rest wait"
                    Segmented {
                        options: [{ id: "important", label: "Important" }, { id: "critical", label: "Critical" }, { id: "off", label: "Off" }]
                        current: Settings.notifFullscreen
                        onPicked: id => Settings.set("notifFullscreen", id)
                    }
                }
                SettingsRow {
                    key: "notifPrivacy"
                    label: "Message privacy"
                    detail: (Settings.notifPrivacy === "always" ? "Chats, mail and texts show who sent them, not what, until you open them"
                          : Settings.notifPrivacy === "never" ? "Chats, mail and texts show in full, the lock screen too"
                          : "Chats, mail and texts show on your desktop; the lock screen shows only who sent them")
                          + (Settings.notifPrivateSenders ? "  ·  Kept private: " + Settings.notifPrivateSenders : "  ·  Passwords and card numbers stay hidden; nothing shows while you share your screen")
                    Segmented {
                        options: [{ id: "lock", label: "Lock screen" }, { id: "always", label: "Always" }, { id: "never", label: "Never" }]
                        current: Settings.notifPrivacy
                        onPicked: id => Settings.set("notifPrivacy", id)
                    }
                }
                SettingsRow {
                    key: "notifToastInstantOpen"
                    label: "Toast opens on first click"
                    detail: Settings.notifToastInstantOpen ? "Tap a toast to open or run its default action" : "Tap to preview, then Open (center and island peek stay explicit)"
                    Toggle {
                        on: Settings.notifToastInstantOpen
                        onToggled: Settings.set("notifToastInstantOpen", !Settings.notifToastInstantOpen)
                    }
                }
                SettingsRow {
                    key: "notifEngageReply"
                    label: "Reply when toast opens"
                    detail: Settings.notifEngageReply ? "Engaging a replyable toast focuses the reply field" : "Show Open and Reply chips first"
                    Toggle {
                        on: Settings.notifEngageReply
                        onToggled: Settings.set("notifEngageReply", !Settings.notifEngageReply)
                    }
                }
                SettingsRow {
                    key: "notifKeepSeenHours"
                    label: "Keep seen notifications"
                    detail: "How long dismissed-but-unread rows stay in the center"
                    Segmented {
                        options: [{ id: "6", label: "6 h" }, { id: "24", label: "1 day" }, { id: "72", label: "3 days" }, { id: "0", label: "Never" }]
                        current: String(Settings.notifKeepSeenHours)
                        onPicked: id => Settings.set("notifKeepSeenHours", Number(id))
                    }
                }
            }
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "A notification you click, answer or open from the center leaves the list, and so does one the app withdraws (you read it there)."
                size: Theme.tSub
                color: Theme.textTertiary
            }
        }
    }
    Component {
        id: assistantPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow {
                    label: "Local assistant"; detail: Settings.assistantOptIn ? "Super+Ctrl+Shift+A opens the overlay (Ollama)" : "Off until you turn this on"
                    Toggle {
                        on: Settings.assistantOptIn
                        onToggled: {
                            Settings.set("assistantOptIn", !Settings.assistantOptIn);
                            if (Settings.assistantOptIn) Settings.set("seenAssistantPrompt", true);
                        }
                    }
                }
                SettingsRow {
                    key: "assistantTerminal"
                    label: "Include the terminal's last command"
                    detail: "When you snapshot a terminal: its last command and output go to the assistant (secrets removed). Off: only its folder"
                    Toggle { on: Settings.assistantTerminal; onToggled: Settings.set("assistantTerminal", !Settings.assistantTerminal) }
                }
                SettingsRow {
                    label: "Crash diagnosis"
                    detail: "Coredump toasts offer Diagnose → local assistant only; nothing sent upstream without you"
                }
            }
        }
    }
    Component {
        id: motionPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow {
                    label: "Reduce motion"
                    detail: Theme.envReduce ? "On for this session (KUWAI_REDUCE_MOTION)"
                        : Theme.hyprStill && !Theme.userReduce ? "On while your desktop mode keeps animations off (Gaming, Battery)"
                        : "Fades instead of slides and springs; digits change without rolling"
                    Toggle { on: Theme.reduceMotion; enabled: !Theme.envReduce && !(Theme.hyprStill && !Theme.userReduce); onToggled: Theme.setReduceMotion(!Theme.reduceMotion) }
                }
            }
            SettingsGroup {
                title: "Seeing"
                SettingsRow {
                    key: "highContrast"
                    label: "Increase contrast"; detail: "Secondary text brighter, edges stronger, the glass nearly opaque (less of what's behind shows through)"
                    Toggle { on: Settings.highContrast; label: "Increase contrast"; onToggled: Settings.set("highContrast", !Settings.highContrast) }
                }
                SettingsRow {
                    key: "textScale"
                    label: "Text size"; detail: "Every label in the shell; rows grow with it"
                    Segmented {
                        options: [{ id: "1", label: "100 %" }, { id: "1.1", label: "110 %" }, { id: "1.2", label: "120 %" }, { id: "1.5", label: "150 %" }, { id: "2", label: "200 %" }]
                        current: String(Settings.textScale)
                        onPicked: id => Settings.set("textScale", Number(id))
                    }
                }
            }
        }
    }
    // Keyboard: layouts (kuwai keyboard), the key that switches between them,
    // and an input method for other scripts (kuwai feature input_method).
    // Read back from kuwai's state file, so the CLI and this page agree.
    Component {
        id: keyboardPage
        Column {
            id: kbPage
            spacing: 18
            readonly property string kuwai: Paths.bin + "/kuwai"
            property var kv: ({})
            FileView {
                path: Paths.stateHome + "/kuwai/state"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: {
                    const o = {};
                    for (const l of text().split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); }
                    kbPage.kv = o;
                }
            }
            readonly property var layouts: String(kv.kb_layout || "us").split(",").filter(x => x)
            readonly property var choices: [
                { id: "us", label: "English (US)" }, { id: "gb", label: "English (UK)" }, { id: "de", label: "German" },
                { id: "fr", label: "French" }, { id: "es", label: "Spanish" }, { id: "it", label: "Italian" },
                { id: "pt", label: "Portuguese" }, { id: "ru", label: "Russian" }, { id: "ua", label: "Ukrainian" },
                { id: "pl", label: "Polish" }, { id: "in", label: "Hindi" }, { id: "jp", label: "Japanese" }]
            function toggle(id) {
                let l = layouts.includes(id) ? layouts.filter(x => x !== id) : layouts.concat([id]);
                if (!l.length) l = ["us"];
                Quickshell.execDetached([kuwai, "keyboard", l.join(",")]);
            }
            SettingsGroup {
                SettingsRow {
                    label: "Layouts"
                    detail: kbPage.layouts.length > 1 ? kbPage.layouts.join(" · ") + " (the first is the default)" : "One layout; pick more to switch between them"
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: kbPage.choices
                        Button {
                            required property var modelData
                            height: Theme.sp(30); size: Theme.tSub
                            text: modelData.label
                            glyph: kbPage.layouts.includes(modelData.id) ? "\u{f012c}" : ""   // a check on the ones in use
                            onClicked: kbPage.toggle(modelData.id)
                        }
                    }
                }
                SettingsRow {
                    label: "Switch layouts with"; detail: "Or any other: kuwai keyboard us,de --switch …"
                    Segmented {
                        options: [{ id: "none", label: "Off" }, { id: "alt-shift", label: "Alt+Shift" }, { id: "win-space", label: "Super+Space" }, { id: "caps", label: "Caps Lock" }]
                        current: kbPage.kv.kb_switch || "none"
                        onPicked: id => Quickshell.execDetached([kbPage.kuwai, "keyboard", "--switch", id])
                    }
                }
            }
            SettingsGroup {
                title: "Key repeat"
                SettingsRow {
                    label: "Delay before repeating"
                    Segmented {
                        options: [{ id: "200", label: "Short" }, { id: "250", label: "Normal" }, { id: "400", label: "Long" }]
                        current: kbPage.kv["ptr.repeat-delay"] || "250"
                        onPicked: id => Quickshell.execDetached([kbPage.kuwai, "pointer", "repeat-delay", id])
                    }
                }
                SettingsRow {
                    label: "Repeat speed"
                    Segmented {
                        options: [{ id: "25", label: "Slow" }, { id: "35", label: "Normal" }, { id: "50", label: "Fast" }]
                        current: kbPage.kv["ptr.repeat-rate"] || "35"
                        onPicked: id => Quickshell.execDetached([kbPage.kuwai, "pointer", "repeat-rate", id])
                    }
                }
            }
            SettingsGroup {
                title: "Function keys"
                SettingsRow {
                    key: "fKeys"
                    label: "F7, F8 and F10"
                    detail: Settings.fKeys === "plain" ? "Apps get them as F7, F8 and F10; brightness and mute stay on their own keys" : "F7 dims, F8 brightens, F10 mutes; Plain leaves them to apps (for keyboards whose Fn row already sends those)"
                    Segmented {
                        options: [{ id: "actions", label: "Brightness, mute" }, { id: "plain", label: "Plain" }]
                        current: Settings.fKeys
                        onPicked: id => Settings.set("fKeys", id)
                    }
                }
                SettingsRow {
                    label: "Shortcuts"
                    detail: "Give any of kuwai's actions keys of your own"
                    Button { height: Theme.sp(30); size: Theme.tSub; text: "Change shortcuts"; onClicked: settings.goTo("shortcuts") }
                }
            }
            SettingsGroup {
                SettingsRow {
                    label: "Input method"
                    detail: "fcitx5 (or ibus) for Japanese, Chinese, Korean, Indic scripts; applies after a reload"
                    Toggle {
                        on: kbPage.kv["feature.input_method"] === "on"
                        onToggled: Quickshell.execDetached([kbPage.kuwai, "feature", "input_method", kbPage.kv["feature.input_method"] === "on" ? "off" : "on"])
                    }
                }
            }
        }
    }
    Component {
        id: shortcutsPage
        ShortcutsPage {}
    }
    Component {
        id: pointerPage
        Column {
            id: ptCol
            spacing: 18
            readonly property string kuwai: Paths.bin + "/kuwai"
            property var kv: ({})
            FileView {
                path: Paths.stateHome + "/kuwai/state"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: {
                    const o = {};
                    for (const l of text().split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); }
                    ptCol.kv = o;
                }
            }
            readonly property var defaults: ({ speed: "-0.5", accel: "flat", "mouse-natural": "off", "trackpad-natural": "on", tap: "on", "trackpad-scroll": "0.7" })
            function get(k) { return kv["ptr." + k] || defaults[k]; }
            function set(k, v) { Quickshell.execDetached([kuwai, "pointer", k, String(v)]); }
            property real pendingSpeed: 0
            Timer { id: speedLater; interval: 200; onTriggered: ptCol.set("speed", ptCol.pendingSpeed.toFixed(2)) }

            SettingsGroup {
                title: "Pointer"
                SettingsRow {
                    label: "Speed"
                    detail: "How far the pointer goes for a move of the mouse or a slide on the trackpad"
                    Slider {
                        Layout.fillWidth: true; Layout.preferredWidth: Theme.sp(180); Layout.maximumWidth: Theme.sp(180); implicitHeight: Theme.sp(28)
                        from: -1; to: 1
                        value: Number(ptCol.get("speed"))
                        valueText: Math.round((value + 1) * 50) + "%"
                        onMoved: v => { ptCol.pendingSpeed = v; speedLater.restart(); }
                    }
                }
                SettingsRow {
                    label: "Acceleration"
                    detail: "Faster moves go further. Off: the same distance every time (most gamers' choice)"
                    Segmented {
                        options: [{ id: "flat", label: "Off" }, { id: "adaptive", label: "On" }]
                        current: ptCol.get("accel")
                        onPicked: id => ptCol.set("accel", id)
                    }
                }
                SettingsRow {
                    label: "Natural scrolling with a mouse"
                    detail: "The page follows the wheel, as on a touch screen"
                    Toggle { on: ptCol.get("mouse-natural") === "on"; onToggled: ptCol.set("mouse-natural", on ? "off" : "on") }
                }
            }
            SettingsGroup {
                title: "Trackpad"
                SettingsRow {
                    label: "Natural scrolling"
                    detail: "Content moves with your fingers"
                    Toggle { on: ptCol.get("trackpad-natural") === "on"; onToggled: ptCol.set("trackpad-natural", on ? "off" : "on") }
                }
                SettingsRow {
                    label: "Tap to click"
                    detail: "A light tap clicks; two fingers right-click"
                    Toggle { on: ptCol.get("tap") === "on"; onToggled: ptCol.set("tap", on ? "off" : "on") }
                }
                SettingsRow {
                    label: "Scrolling speed"
                    Segmented {
                        options: [{ id: "0.4", label: "Slow" }, { id: "0.7", label: "Normal" }, { id: "1.2", label: "Fast" }]
                        current: ptCol.get("trackpad-scroll")
                        onPicked: id => ptCol.set("trackpad-scroll", id)
                    }
                }
            }
        }
    }
    Component {
        id: displaysPage
        Column {
            id: dpCol
            spacing: 18
            readonly property string kuwai: Paths.bin + "/kuwai"
            property var screens: []
            property bool read: false
            function load() { if (!reader.running) reader.running = true; }
            Component.onCompleted: load()
            Process {
                id: reader
                command: ["hyprctl", "repl", "return kuwai.screens_json()"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const t = text.trim(), i = t.indexOf("[");
                        try { dpCol.screens = i >= 0 ? JSON.parse(t.slice(i)) : []; } catch (e) { dpCol.screens = []; }
                        dpCol.read = true;
                    }
                }
                onExited: dpCol.read = true
            }
            Timer { id: reread; interval: 700; onTriggered: dpCol.load() }
            function set(name, field, value) {
                Quickshell.execDetached([kuwai, "screen", name, field, String(value)]);
                reread.restart();
            }
            function scales(cur) {
                const std = [1, 1.25, 1.5, 2];
                const r = Math.round(cur * 100) / 100;
                return (std.some(v => Math.abs(v - cur) < 0.01) ? std : std.concat([r]).sort((a, b) => a - b))
                    .map(v => ({ id: String(v), label: v + "×" }));
            }
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                visible: dpCol.screens.length === 0 && !dpCol.read
                text: "Reading your screens…"
                size: Theme.tSub; color: Theme.textTertiary
            }
            Notice {
                visible: dpCol.screens.length === 0 && dpCol.read
                glyph: "\u{f0026}"
                title: "Couldn't read your screens"
                detail: "Hyprland didn't answer"
                action: "Try again"
                onActed: { dpCol.read = false; dpCol.load(); }
            }
            Repeater {
                model: dpCol.screens
                SettingsGroup {
                    required property var modelData
                    title: modelData.description ? modelData.description + " · " + modelData.name : modelData.name
                    SettingsRow {
                        label: "Scale"
                        detail: modelData.size + " pixels"
                        Segmented {
                            options: dpCol.scales(modelData.scale)
                            current: String(dpCol.scales(modelData.scale).find(o => Math.abs(Number(o.id) - modelData.scale) < 0.01).id)
                            onPicked: id => dpCol.set(modelData.name, "scale", id)
                        }
                    }
                    SettingsRow {
                        visible: modelData.rates.length > 1
                        label: "Refresh rate"
                        Segmented {
                            options: modelData.rates.map(r => ({ id: String(r), label: r + " Hz" }))
                            current: String(modelData.rate)
                            onPicked: id => dpCol.set(modelData.name, "rate", id)
                        }
                    }
                    SettingsRow {
                        visible: modelData.changed
                        label: "Changed here"
                        detail: "Over what monitors.lua says for this screen"
                        Button { height: Theme.sp(30); size: Theme.tSub; text: "Use monitors.lua"; onClicked: dpCol.set(modelData.name, "reset", "") }
                    }
                }
            }
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Where screens sit and which is which stay in ~/.config/kuwai/hypr/monitors.lua."
                size: Theme.tFootnote; color: Theme.textTertiary
            }
        }
    }
    Component {
        id: islandRestPage
        Column {
            spacing: 18
            SettingsGroup {
                title: "The island at rest"
                // Two looks for the same island. Minimal: a mini notch with the
                // time, or whatever is alive (music, a moment, a password, a
                // recording). Hidden: nothing at all until you near the top,
                // press Ctrl+Alt+W, or something needs you; then the same
                // mini notch. Near the top, either shows the full row.
                SettingsRow {
                    id: styleRow
                    readonly property string style: Settings.islandTucked ? "hidden" : Settings.islandRest === "full" ? "full" : "minimal"
                    label: "Style"
                    detail: style === "hidden" ? "Out of the way: it appears near the top edge, with Ctrl+Alt+W, or when something needs you. Windows get the whole screen."
                          : style === "full" ? "Workspaces, time and status, always"
                          : "Just the time, or what's alive: music, a moment, a password, a recording. Near the top edge for the rest."
                    Segmented {
                        options: [{ id: "minimal", label: "Minimal" }, { id: "hidden", label: "Hidden" }, { id: "full", label: "Everything" }]
                        current: styleRow.style
                        onPicked: id => {
                            Settings.set("islandTucked", id === "hidden");
                            Settings.set("islandRest", id === "full" ? "full" : "minimal");
                        }
                    }
                }
                SettingsRow {
                    key: "islandProximity"
                    label: "Reveal on approach"; detail: Settings.islandProximity ? "The pointer coming within 30–60 px of the island shows it" : "Only touching the top edge shows it"
                    Toggle { on: Settings.islandProximity; onToggled: Settings.set("islandProximity", !Settings.islandProximity) }
                }
                SettingsRow {
                    label: "Quick switch"; detail: "Shown first in the hover shelf: " + (Settings.quickPrimary || "caffeine") + ". Hold another one in the shelf to make it first."
                }
            }
            SettingsGroup {
                title: "Idle projects"
                SettingsRow {
                    key: "sweepMark"
                    label: "Idle projects mark"; detail: "A small mark when sweep finds old projects holding space; rest on it to see which. Needs sweep installed"
                    Toggle { on: Settings.sweepMark; label: "Idle projects mark"; onToggled: Settings.set("sweepMark", !Settings.sweepMark) }
                }
                SettingsRow {
                    key: "sweepMinGB"
                    visible: Settings.sweepMark
                    label: "Show it from"; detail: "How much idle space is worth a mark"
                    Segmented {
                        options: [5, 10, 20, 50].map(n => ({ id: String(n), label: n + " GB" }))
                        current: String(Settings.sweepMinGB)
                        onPicked: id => Settings.set("sweepMinGB", Number(id))
                    }
                }
            }
        }
    }
    Component {
        id: powerPage
        Column {
            spacing: 18
            // Wellbeing (services/Wellbeing): two quiet nudges on the notch.
            SettingsGroup {
                title: "Wellbeing"
                SettingsRow {
                    key: "breakReminders"
                    label: "Break reminders"; detail: "A moment after a long stretch at the screen; five idle minutes or a lock counts as a break"
                    Toggle { on: Settings.breakReminders; label: "Break reminders"; onToggled: Settings.set("breakReminders", !Settings.breakReminders) }
                }
                SettingsRow {
                    key: "breakMins"
                    visible: Settings.breakReminders
                    label: "Every"
                    Segmented {
                        options: [{ id: "40", label: "40 min" }, { id: "50", label: "50 min" }, { id: "60", label: "1 h" }, { id: "90", label: "90 min" }]
                        current: String(Settings.breakMins)
                        onPicked: id => Settings.set("breakMins", Number(id))
                    }
                }
                SettingsRow {
                    key: "sleepReminder"
                    label: "Bedtime nudge"; detail: "Past this time, a calm reminder to wind down (three at most, 45 min apart)"
                    Toggle { on: Settings.sleepReminder; label: "Bedtime nudge"; onToggled: Settings.set("sleepReminder", !Settings.sleepReminder) }
                }
                SettingsRow {
                    key: "sleepAt"
                    visible: Settings.sleepReminder
                    label: "After"
                    Segmented {
                        options: [{ id: "23:30", label: "23:30" }, { id: "00:00", label: "00:00" }, { id: "00:30", label: "00:30" }, { id: "01:00", label: "01:00" }]
                        current: Settings.sleepAt
                        onPicked: id => Settings.set("sleepAt", id)
                    }
                }
            }
            SettingsGroup {
                SettingsRow {
                    key: "idleOwner"
                    label: "Who handles idle"; detail: Idle.ownerError || (Idle.confirmedOwner === "shell" ? "Active: shell — dims, locks and sleeps. A requested handoff waits for readiness." : "Active: hypridle (~/.config/hypr/hypridle.conf); the rows below don't apply")
                    Segmented {
                        options: [{ id: "shell", label: "Shell" }, { id: "hypridle", label: "hypridle" }]
                        current: Settings.idleOwner
                        onPicked: id => Settings.set("idleOwner", id)
                    }
                }
                SettingsRow {
                    key: "idleNoSleepWhilePlaying"
                    label: "Don't sleep while music plays"
                    Toggle { on: Settings.idleNoSleepWhilePlaying; onToggled: Settings.set("idleNoSleepWhilePlaying", !Settings.idleNoSleepWhilePlaying) }
                }
                SettingsRow {
                    key: "idleScreensWhileWork"
                    label: "Keep screens on while work runs"
                    detail: "While an agent, a T3 thread or an update is working, on power, the screens dim and lock but don't turn off (an external monitor that sleeps can disconnect, and its windows move)"
                    Toggle { on: Settings.idleScreensWhileWork; onToggled: Settings.set("idleScreensWhileWork", !Settings.idleScreensWhileWork) }
                }
                SettingsRow {
                    key: "caffeineMode"
                    label: "Keep awake"
                    detail: Settings.caffeineMode === "login" ? "Caffeine comes on with each login (it still ends with the session)"
                          : Settings.caffeineMode === "work" ? "No sleep from idle while an agent, a T3 thread or an update is working, on power. Screens still dim and lock."
                          : "Only when you turn Caffeine on"
                    Segmented {
                        options: [{ id: "manual", label: "Manual" }, { id: "login", label: "At login" }, { id: "work", label: "While work runs" }]
                        current: Settings.caffeineMode
                        onPicked: id => Settings.set("caffeineMode", id)
                    }
                }
            }
            SettingsGroup {
                title: "On power"
                opacity: Settings.idleOwner === "shell" ? 1 : 0.45
                SettingsRow { key: "idleDimAc"; label: "Dim the screen"; SecondsChoice { key: "idleDimAc"; values: [120, 180, 300, 0] } }
                SettingsRow { key: "idleLockAc"; label: "Lock"; SecondsChoice { key: "idleLockAc"; values: [180, 300, 900, 0] } }
                SettingsRow { key: "idleOffAc"; label: "Screen off"; SecondsChoice { key: "idleOffAc"; values: [330, 600, 1800, 0] } }
                SettingsRow { key: "idleSleepAc"; label: "Sleep"; SecondsChoice { key: "idleSleepAc"; values: [1800, 3600, 0] } }
            }
            SettingsGroup {
                title: "On battery"
                opacity: Settings.idleOwner === "shell" ? 1 : 0.45
                SettingsRow { key: "idleDimBattery"; label: "Dim the screen"; SecondsChoice { key: "idleDimBattery"; values: [60, 120, 300, 0] } }
                SettingsRow { key: "idleLockBattery"; label: "Lock"; SecondsChoice { key: "idleLockBattery"; values: [120, 180, 600, 0] } }
                SettingsRow { key: "idleOffBattery"; label: "Screen off"; SecondsChoice { key: "idleOffBattery"; values: [210, 300, 900, 0] } }
                SettingsRow { key: "idleSleepBattery"; label: "Sleep"; SecondsChoice { key: "idleSleepBattery"; values: [600, 900, 1800, 0] } }
            }
            Label {
                width: parent.width; wrapMode: Text.WordWrap; size: Theme.tSub; color: Theme.textTertiary
                text: "Caffeine (the cup in the island) holds all of these off. The screen always locks before the laptop sleeps."
            }
        }
    }
    Component {
        id: saverPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow {
                    key: "screensaverWhen"
                    label: "Show the screensaver"
                    detail: Settings.screensaverWhen === "caffeine" ? "While Caffeine keeps the screen on, after a while of no input" : Settings.screensaverWhen === "always" ? "Whenever you're away, before the screen fades and locks (after " + Idle.saverAfterText + ")" : "Never"
                    Segmented {
                        options: [{ id: "always", label: "Always" }, { id: "caffeine", label: "With Caffeine" }, { id: "off", label: "Off" }]
                        current: Settings.screensaverWhen
                        onPicked: id => Settings.set("screensaverWhen", id)
                    }
                }
                SettingsRow {
                    key: "screensaverMins"
                    label: "After"
                    detail: Settings.screensaverWhen === "always" && Idle.saverAfter < Settings.screensaverMins * 60 ? "Comes " + Idle.saverAfterText + " in, before the lock" : ""
                    Segmented {
                        options: [1, 3, 5, 10].map(n => ({ id: String(n), label: n + " min" }))
                        current: String(Settings.screensaverMins)
                        onPicked: id => Settings.set("screensaverMins", Number(id))
                    }
                }
                SettingsRow {
                    key: "screensaverStyle"
                    label: "Look"; detail: Settings.screensaverStyle === "dusk" ? "A slow dusk sky with drifting petals"
                        : Settings.screensaverStyle === "borealis" ? "Northern lights in your theme's colour over a night sky"
                        : Settings.screensaverStyle === "night" ? "A dark film on the screen you were using; black on the others"
                        : Settings.screensaverStyle === "live" ? "Your live wallpaper, full screen" : "Your wallpaper, still, with the time"
                    Segmented {
                        options: [{ id: "dusk", label: "Dusk" }, { id: "borealis", label: "Borealis" }, { id: "night", label: "Night" }, { id: "live", label: "Live" }, { id: "still", label: "Still" }]
                        current: Settings.screensaverStyle
                        onPicked: id => Settings.set("screensaverStyle", id)
                    }
                }
                SettingsRow {
                    key: "screensaverClip"
                    visible: Settings.screensaverStyle === "night"
                    label: "Film"; detail: "Files in ~/.local/share/kuwai-data/screensavers"
                    Segmented {
                        options: [{ id: "smoke-soft", label: "Smoke" }, { id: "aurora", label: "Aurora" }, { id: "stars-lake", label: "Stars" }]
                        current: Settings.screensaverClip
                        onPicked: id => Settings.set("screensaverClip", id)
                    }
                }
                SettingsRow {
                    label: "Preview"; detail: "Any input ends it"
                    Button { height: Theme.sp(30); size: Theme.tSub; text: "Start now"; onClicked: Quickshell.execDetached([settings.kuwai, "screensaver", "start"]) }
                }
            }
            SettingsGroup {
                title: "Wallpaper"
                SettingsRow {
                    key: "wallTransition"
                    label: "Wallpaper change"
                    detail: Settings.wallTransition === "shards" ? "The new picture arrives in cut pieces, spreading from the island"
                          : Settings.wallTransition === "glass" ? "The new picture grows from the island behind a lens of glass"
                          : Settings.wallTransition === "contour" ? "The new picture's lines draw in from the island, then it fills in behind them"
                          : "Its subject first when it has been cut out (kuwai-wallmap --install), otherwise pieces or glass in turn"
                    Segmented {
                        options: [{ id: "auto", label: "Auto" }, { id: "shards", label: "Pieces" }, { id: "contour", label: "Lines" }, { id: "glass", label: "Glass" }]
                        current: Settings.wallTransition
                        onPicked: id => Settings.set("wallTransition", id)
                    }
                }
            }
            SettingsGroup {
                title: "Live wallpaper"
                SettingsRow {
                    key: "liveOnBattery"
                    label: "Keep playing on battery"; detail: "Off: it pauses on battery to save power"
                    Toggle { on: Settings.liveOnBattery; onToggled: Settings.set("liveOnBattery", !Settings.liveOnBattery) }
                }
            }
        }
    }
    Component {
        id: timePage
        Column {
            spacing: 18
            SettingsGroup {
                title: "Reminders"
                SettingsRow {
                    visible: Reminders.items.length === 0
                    label: "None"; detail: "Type \"remind me in 20m tea\" or \"tomorrow 9am dentist\" in the launcher, or press Super+Ctrl+Shift+J"
                }
                Repeater {
                    model: Reminders.items
                    SettingsRow {
                        id: remRow
                        required property var modelData
                        label: modelData.text; detail: Reminders.when(modelData.at)
                        Button { height: Theme.sp(30); size: Theme.tSub; text: "Remove"; onClicked: Reminders.cancel(remRow.modelData.id) }
                    }
                }
            }
            SettingsGroup {
                title: "Alarms"
                SettingsRow {
                    visible: Alarms.items.length === 0
                    label: "None"; detail: "Type \"alarm 7:30\" in the launcher"
                }
                Repeater {
                    model: Alarms.items
                    SettingsRow {
                        id: alRow
                        required property var modelData
                        label: modelData.label; detail: Dates.weekdayTime(modelData.at)
                        Button { height: Theme.sp(30); size: Theme.tSub; text: "Remove"; onClicked: Alarms.cancel(alRow.modelData.id) }
                    }
                }
                SettingsRow {
                    label: "Wake from sleep"
                    detail: Alarms.canWake ? "On: the laptop wakes a minute before an alarm" : "Off: alarms ring when the laptop is next awake. Turn on once with: sudo /usr/local/lib/kuwai/current/system/install (root's copy of kuwai, which kuwai setup puts in place)"
                }
            }
            SettingsGroup {
                title: "Notes and focus"
                SettingsRow { label: "Quick note"; detail: "Super+Ctrl+J, or \"note …\" in the launcher: a line in " + Notes.file.replace(Quickshell.env("HOME"), "~")
                    Button { height: Theme.sp(30); size: Theme.tSub; text: "Open"; onClicked: Notes.open() } }
                SettingsRow { label: "Pomodoro"; detail: "\"pomodoro\" in the launcher: 25 min focus, 5 min break, ×4, then 15" }
            }
        }
    }
    Component {
        id: workspacesPage
        Column {
            spacing: 18
            SettingsGroup {
                title: "With more than one screen"
                SettingsRow {
                    label: "Workspaces"
                    detail: Island.desktops ? "Together: Super+3 or Super+Ctrl+→ switch every screen at once; one row of pills everywhere"
                                            : "Per screen: each screen switches on its own (the one you're on); its pills are its own"
                    Segmented {
                        options: [{ id: "per_screen", label: "Per screen" }, { id: "desktops", label: "All together" }]
                        current: Island.desktops ? "desktops" : "per_screen"
                        onPicked: id => Quickshell.execDetached([Paths.bin + "/kuwai", "feature", "desktops", id === "desktops" ? "on" : "off"])
                    }
                }
                SettingsRow {
                    key: "workspaceCount"
                    label: "Pills shown at least"; detail: "More appear as you use them"
                    Segmented {
                        options: [{ id: "3", label: "3" }, { id: "5", label: "5" }, { id: "7", label: "7" }, { id: "10", label: "10" }]
                        current: String(Settings.workspaceCount)
                        onPicked: id => Settings.set("workspaceCount", parseInt(id))
                    }
                }
            }
            SettingsGroup {
                title: "Keys"
                SettingsRow { label: "Go to 1–9"; detail: "Super+1…9" }
                SettingsRow { label: "Previous / next"; detail: "Super+Ctrl+← →  (Shift: take the window along)" }
                SettingsRow { label: "Move a window there"; detail: "Super+Shift+1…9  (Alt instead of Shift: send it, stay here)" }
                SettingsRow { label: "Window to the other screen"; detail: "Super+Ctrl+Alt+← →" }
                SettingsRow { label: "See everything"; detail: "Super+Tab or Super+Ctrl+↑  (Mission Control)" }
            }
        }
    }
    Component {
        id: clipboardPage
        Column {
            spacing: 18
            SettingsGroup {
                title: "Order"
                SettingsRow {
                    key: "clipPinsFirst"
                    label: "Pinned first"; detail: "Off: pins sit in their place by time, with a pin. Type @pin to see only them."
                    Toggle { on: Settings.clipPinsFirst; onToggled: Settings.set("clipPinsFirst", !Settings.clipPinsFirst) }
                }
            }
            SettingsGroup {
                title: "Search"
                SettingsRow {
                    label: "Filters you can type"; detail: "@pin @image @text @file @link @code @color @secret, and @today @week; mix with words"
                }
            }
        }
    }
    Component {
        id: updatesPage
        Column {
            spacing: 18
            SettingsGroup {
                title: "Checking"
                SettingsRow {
                    key: "updatesCheckHours"
                    label: "Check every"; detail: Settings.updatesCheckHours > 0 ? Settings.updatesCheckHours + (Settings.updatesCheckHours === 1 ? " hour" : " hours") + " (needs no password)" : "Only when you open Software Update"
                    Segmented {
                        options: [{ id: "0", label: "Never" }, { id: "1", label: "1 h" }, { id: "3", label: "3 h" }, { id: "12", label: "12 h" }]
                        current: String(Settings.updatesCheckHours)
                        onPicked: id => Settings.set("updatesCheckHours", parseInt(id))
                    }
                }
                SettingsRow {
                    key: "updatesAnnounce"
                    label: "Say when updates appear"; detail: "A short note from the island when there are new ones"
                    Toggle { on: Settings.updatesAnnounce; onToggled: Settings.set("updatesAnnounce", !Settings.updatesAnnounce) }
                }
                SettingsRow {
                    key: "updatesFlatpak"
                    label: "Include Flatpak apps"; detail: "Sandboxed and signed; your own installs need no password"
                    Toggle { on: Settings.updatesFlatpak; onToggled: Settings.set("updatesFlatpak", !Settings.updatesFlatpak) }
                }
                SettingsRow {
                    key: "updatesPruneCache"
                    label: "Prune the package cache after updating"; detail: "Keeps the installed and one older version of each package; removed packages' files go. Off keeps every downloaded file for rolling back"
                    Toggle { on: Settings.updatesPruneCache; onToggled: Settings.set("updatesPruneCache", !Settings.updatesPruneCache) }
                }
            }
            SettingsGroup {
                title: "AUR"
                SettingsRow {
                    key: "updatesAutoRoutine"
                    label: "Approve version bumps by themselves"
                    detail: "Only when the build script moved nothing but versions and checksums, nothing is flagged, and the package is established in the AUR (100+ votes or popular, maintained, a year old). The program inside a -bin package is never reviewed: trust its author, not the label."
                    Toggle { on: Settings.updatesAutoRoutine; onToggled: Settings.set("updatesAutoRoutine", !Settings.updatesAutoRoutine) }
                }
                SettingsRow {
                    label: "Trusted packages"; detail: Updates.trusted.length ? Updates.trusted.join(", ") : "None: trust one from its review"
                    Button { height: Theme.sp(30); size: Theme.tSub; visible: Updates.trusted.length > 0; text: "Open Software Update"; onClicked: Island.open("updates", Island.screen, "pointer", "island") }
                }
            }
        }
    }
    Component {
        id: aboutPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow { label: "Shell"; Label { text: "Quickshell " + (Quickshell.version || ""); size: Theme.tBody; color: Theme.textSecondary } }
                SettingsRow { label: "Settings file"; Label { text: "~/.config/kuwai/settings.json"; size: Theme.tBody; color: Theme.textSecondary; font.family: Theme.fontMono } }
                SettingsRow {
                    label: "Backups"; detail: "Your settings, Hyprland files, reminders, alarms, notes and pins: daily and before every update of the desktop, the newest 30. Put one back: kuwai backup restore NAME"
                    Button { height: Theme.sp(30); size: Theme.tSub; text: "Back up now"; onClicked: Quickshell.execDetached([settings.kuwai, "backup"]) }
                }
                SettingsRow {
                    label: "Restart the shell"; detail: "Reloads everything; notifications stay"
                    Button { height: Theme.sp(30); size: Theme.tSub; text: "Restart"; onClicked: Quickshell.execDetached([settings.kuwai, "restart"]) }
                }
            }
        }
    }
}
