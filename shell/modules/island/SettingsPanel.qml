// Settings, grown out of the island (Super+, or the launcher's "Settings"):
// a sidebar of sections and grouped rows, like System Settings. Every row is
// a real setting (config/Settings, ~/.config/rice/settings.json); changes
// apply at once, nothing to save. Keys: ↑↓ section, type (or / or Ctrl+F)
// to search every row of every page, Esc clears the search, then closes.
//
//   ▣ Bar & Island     Bar & Island
//   ▣ Clock & Date     ┌──────────────────────────────────────────┐
//   ▣ Notifications    │ Top bar              [ Waybar | Island ] │
//   ▣ Motion           │ Workspaces at rest                  (●) │
//   ▣ About            └──────────────────────────────────────────┘
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui
import qs.services

FocusScope {
    id: settings
    focus: true

    implicitWidth: 780
    implicitHeight: 520

    readonly property string rice: Paths.bin + "/rice"
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
        sideFlick.revealAt(i * 46, 44);
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
        width: Math.round(212 * Theme.textScale)   // grows with Text size
        height: parent.height
        color: Qt.rgba(1, 1, 1, 0.03)
        // The search sits where the title was (System Settings): the panel
        // says "Settings" in its own header row (Accessible name below).
        Rectangle {
            id: searchBox
            x: 10; y: 12
            width: parent.width - 20
            height: 32
            radius: 9
            color: Qt.rgba(1, 1, 1, search.activeFocus ? 0.10 : 0.06)
            border.width: 1
            border.color: search.activeFocus ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.06)
            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
            Behavior on border.color { ColorAnimation { duration: Theme.hoverMs } }
            Text {
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
                font.pixelSize: 13
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
                    size: 13
                    color: Theme.textTertiary
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search settings"
                Accessible.description: !settings.query ? "Type to find any setting"
                    : settings.results.length === 1 ? "1 result" : settings.results.length + " results"
            }
            Text {
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
          x: 10; y: 54
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
                    height: 36
                    radius: 9
                    color: on ? Qt.rgba(1, 1, 1, 0.12) : itemArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    Rectangle {
                        id: chip
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: 7
                        color: item.modelData.tint
                        Text { anchors.centerIn: parent; text: item.modelData.glyph; font.family: Theme.fontGlyph; font.pixelSize: 14; color: "white" }
                    }
                    Label { anchors { left: chip.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: item.modelData.label; size: 13; weight: item.on ? Theme.wMedium : Theme.wRegular }
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
                    height: 44
                    radius: 9
                    color: on ? Qt.rgba(1, 1, 1, 0.12) : resArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    Rectangle {
                        id: resChip
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 6
                        color: res.modelData.section.tint
                        Text { anchors.centerIn: parent; text: res.modelData.section.glyph; font.family: Theme.fontGlyph; font.pixelSize: 13; color: "white" }
                    }
                    Column {
                        anchors { left: resChip.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: res.modelData.row ? res.modelData.row.label : res.modelData.section.label
                            size: 13; weight: res.on ? Theme.wMedium : Theme.wRegular
                        }
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: res.modelData.row ? res.modelData.section.label + (res.modelData.row.group ? " · " + res.modelData.row.group : "") : "Page"
                            size: 11; color: Theme.textTertiary
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
                Label { text: "No Results"; size: 13; weight: Theme.wMedium; color: Theme.textSecondary }
                Label { width: parent.width; wrapMode: Text.Wrap; text: "Nothing in Settings matches “" + settings.query + "”. Try a shorter word."; size: 11; color: Theme.textTertiary }
            }
        }
        }
        ScrollHint { flickable: sideFlick; anchors { right: parent.right; top: sideFlick.top; bottom: sideFlick.bottom; rightMargin: 2 } }
    }
    Rectangle { x: side.width; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.07) }

    // ── Content ──────────────────────────────────────────────────────────
    Item {
        id: content
        x: side.width + 1
        width: parent.width - x
        height: parent.height

        Label { id: heading; x: 28; y: 20; text: (settings.sections[settings.current] || {}).label || ""; size: 20; weight: Theme.wSemibold }

        Flickable {
            id: pageFlick
            x: 28; y: 62
            width: parent.width - 56
            height: parent.height - y - 16
            contentHeight: page.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: page
                width: parent.width
                sourceComponent: [barPage, clockPage, notifPage, assistantPage, motionPage, keyboardPage, islandRestPage, workspacesPage, powerPage, saverPage, timePage, clipboardPage, updatesPage, aboutPage][settings.current]
            }
        }
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
                        onPicked: id => Quickshell.execDetached([settings.rice, "bar", id])
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
                    label: "Weather"; detail: "In the island, for " + (Settings.weatherLocation || "where you are") + "  ·  rice set weatherLocation \"City\""
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
                    key: "notifRedactSensitive"
                    label: "Hide sensitive message text"
                    detail: Settings.notifRedactSensitive ? "Chat/mail: show who, not the body, until you Open" : "Full text on peek, toasts and center"
                    Toggle {
                        on: Settings.notifRedactSensitive
                        onToggled: Settings.set("notifRedactSensitive", !Settings.notifRedactSensitive)
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
                size: 12
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
                    label: "Reduce motion"; detail: "Fades instead of slides and springs; digits change without rolling"
                    Toggle { on: Theme.reduceMotion; enabled: !Theme.envReduce; onToggled: Theme.setReduceMotion(!Theme.reduceMotion) }
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
                        options: [{ id: "1", label: "100 %" }, { id: "1.1", label: "110 %" }, { id: "1.2", label: "120 %" }]
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
                path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/kuwai/state"
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
                        PillButton {
                            required property var modelData
                            text: modelData.label
                            tint: kbPage.layouts.includes(modelData.id) ? Qt.alpha(Theme.accent, 0.35) : "transparent"
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
                    label: "Who handles idle"; detail: Settings.idleOwner === "shell" ? "The shell: dims, fades, locks and sleeps, aware of Caffeine and of music playing" : "hypridle (~/.config/hypr/hypridle.conf); the rows below don't apply"
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
            }
            SettingsGroup {
                title: "On power"
                opacity: Settings.idleOwner === "shell" ? 1 : 0.45
                SettingsRow { key: "idleDimAc"; label: "Dim the screen"; SecondsChoice { key: "idleDimAc"; values: [120, 240, 600, 0] } }
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
                width: parent.width; wrapMode: Text.WordWrap; size: 12; color: Theme.textTertiary
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
                    detail: Settings.screensaverWhen === "caffeine" ? "While Caffeine keeps the screen on, after a while of no input" : Settings.screensaverWhen === "always" ? "Whenever you're away, before the lock" : "Never"
                    Segmented {
                        options: [{ id: "caffeine", label: "With Caffeine" }, { id: "always", label: "Always" }, { id: "off", label: "Off" }]
                        current: Settings.screensaverWhen
                        onPicked: id => Settings.set("screensaverWhen", id)
                    }
                }
                SettingsRow {
                    key: "screensaverMins"
                    label: "After"
                    Segmented {
                        options: [1, 3, 5, 10].map(n => ({ id: String(n), label: n + " min" }))
                        current: String(Settings.screensaverMins)
                        onPicked: id => Settings.set("screensaverMins", Number(id))
                    }
                }
                SettingsRow {
                    key: "screensaverStyle"
                    label: "Look"; detail: Settings.screensaverStyle === "dusk" ? "A slow dusk sky with drifting petals"
                        : Settings.screensaverStyle === "night" ? "A dark film on the screen you were using; black on the others"
                        : Settings.screensaverStyle === "live" ? "Your live wallpaper, full screen" : "Your wallpaper, still, with the time"
                    Segmented {
                        options: [{ id: "dusk", label: "Dusk" }, { id: "night", label: "Night" }, { id: "live", label: "Live" }, { id: "still", label: "Still" }]
                        current: Settings.screensaverStyle
                        onPicked: id => Settings.set("screensaverStyle", id)
                    }
                }
                SettingsRow {
                    key: "screensaverClip"
                    visible: Settings.screensaverStyle === "night"
                    label: "Film"; detail: "Files in ~/.local/share/rice/screensavers"
                    Segmented {
                        options: [{ id: "smoke-soft", label: "Smoke" }, { id: "aurora", label: "Aurora" }, { id: "stars-lake", label: "Stars" }]
                        current: Settings.screensaverClip
                        onPicked: id => Settings.set("screensaverClip", id)
                    }
                }
                SettingsRow {
                    label: "Preview"; detail: "Any input ends it"
                    PillButton { text: "Start now"; onClicked: Quickshell.execDetached([settings.rice, "screensaver", "start"]) }
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
                        PillButton { text: "Remove"; onClicked: Reminders.cancel(remRow.modelData.id) }
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
                        label: modelData.label; detail: Qt.formatDateTime(new Date(modelData.at), "ddd " + (Settings.clock24 ? "HH:mm" : "h:mm AP"))
                        PillButton { text: "Remove"; onClicked: Alarms.cancel(alRow.modelData.id) }
                    }
                }
                SettingsRow {
                    label: "Wake from sleep"
                    detail: Alarms.canWake ? "On: the laptop wakes a minute before an alarm" : "Off: alarms ring when the laptop is next awake. Turn on once with: sudo " + Paths.root.replace(Quickshell.env("HOME"), "~") + "/system/install"
                }
            }
            SettingsGroup {
                title: "Notes and focus"
                SettingsRow { label: "Quick note"; detail: "Super+Ctrl+J, or \"note …\" in the launcher: a line in " + Notes.file.replace(Quickshell.env("HOME"), "~")
                    PillButton { text: "Open"; onClicked: Notes.open() } }
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
                    PillButton { visible: Updates.trusted.length > 0; text: "Open Software Update"; onClicked: Island.open("updates", Island.screen, "pointer", "island") }
                }
            }
        }
    }
    Component {
        id: aboutPage
        Column {
            spacing: 18
            SettingsGroup {
                SettingsRow { label: "Shell"; Label { text: "Quickshell " + (Quickshell.version || ""); size: 13; color: Theme.textSecondary } }
                SettingsRow { label: "Settings file"; Label { text: "~/.config/rice/settings.json"; size: 13; color: Theme.textSecondary; font.family: Theme.fontMono } }
                SettingsRow {
                    label: "Backups"; detail: "Your settings, Hyprland files, reminders, alarms, notes and pins: daily and before every update of the desktop, the newest 30. Put one back: rice backup restore NAME"
                    PillButton { text: "Back up now"; onClicked: Quickshell.execDetached([settings.rice, "backup"]) }
                }
                SettingsRow {
                    label: "Restart the shell"; detail: "Reloads everything; notifications stay"
                    PillButton { text: "Restart"; onClicked: Quickshell.execDetached([settings.rice, "restart"]) }
                }
            }
        }
    }
}
