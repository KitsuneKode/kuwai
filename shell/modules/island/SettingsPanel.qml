// Settings, grown out of the island (Super+, or the launcher's "Settings"):
// a sidebar of sections and grouped rows, like System Settings. Every row is
// a real setting (config/Settings, ~/.config/rice/settings.json); changes
// apply at once, nothing to save. Keys: ↑↓ section, Esc closes.
//
//   ▣ Bar & Island     Bar & Island
//   ▣ Clock & Date     ┌──────────────────────────────────────────┐
//   ▣ Notifications    │ Top bar              [ Waybar | Island ] │
//   ▣ Motion           │ Workspaces at rest                  (●) │
//   ▣ About            └──────────────────────────────────────────┘
import QtQuick
import Quickshell
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
    function goTo(page) {
        const i = sections.findIndex(x => x.id === page);
        if (i >= 0) current = i;
        if (page) Island.settingsPage = "";
    }
    Component.onCompleted: goTo(Island.settingsPage)
    Connections { target: Island; function onSettingsPageChanged() { settings.goTo(Island.settingsPage); } }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) current = (current + 1) % sections.length;
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) current = (current + sections.length - 1) % sections.length;
        else return;
        event.accepted = true;
    }

    // ── Sidebar ──────────────────────────────────────────────────────────
    Rectangle {
        id: side
        width: 212
        height: parent.height
        color: Qt.rgba(1, 1, 1, 0.03)
        Label { x: 22; y: 22; text: "Settings"; size: 13; weight: Theme.wSemibold; color: Theme.textTertiary }
        Column {
            x: 10; y: 52
            width: parent.width - 20
            spacing: 2
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
                }
            }
        }
    }
    Rectangle { x: side.width; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.07) }

    // ── Content ──────────────────────────────────────────────────────────
    Item {
        id: content
        x: side.width + 1
        width: parent.width - x
        height: parent.height

        Label { id: heading; x: 28; y: 20; text: settings.sections[settings.current].label; size: 20; weight: Theme.wSemibold }

        Flickable {
            x: 28; y: 62
            width: parent.width - 56
            height: parent.height - y - 16
            contentHeight: page.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: page
                width: parent.width
                sourceComponent: [barPage, clockPage, notifPage, assistantPage, motionPage, islandRestPage, workspacesPage, powerPage, saverPage, timePage, clipboardPage, updatesPage, aboutPage][settings.current]
            }
        }
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
                    label: "Shape"; detail: "A floating island, or a notch hanging from the top edge"
                    Segmented {
                        options: [{ id: "floating", label: "Island" }, { id: "notch", label: "Notch" }]
                        current: Settings.islandStyle
                        onPicked: id => Settings.set("islandStyle", id)
                    }
                }
                SettingsRow {
                    label: "Workspaces at rest"; detail: "Capsules beside the clock"
                    Toggle { on: Settings.restWorkspaces; onToggled: Settings.set("restWorkspaces", !Settings.restWorkspaces) }
                }
                SettingsRow {
                    label: "Signal and battery at rest"
                    Toggle { on: Settings.restStatus; onToggled: Settings.set("restStatus", !Settings.restStatus) }
                }
                SettingsRow {
                    label: "Workspaces shown"; detail: "At least this many; more appear as they fill"
                    Segmented {
                        options: [3, 5, 7, 10].map(n => ({ id: String(n), label: String(n) }))
                        current: String(Settings.workspaceCount)
                        onPicked: id => Settings.set("workspaceCount", Number(id))
                    }
                }
                SettingsRow {
                    label: "Agent limit alerts"; detail: "When a harness quota crosses 90% or hits the cap, peek once from the island (provider, account, window) — not a badge on the clock"
                    Toggle { on: Settings.islandAgentUsage; onToggled: Settings.set("islandAgentUsage", !Settings.islandAgentUsage) }
                }
            }
            SettingsGroup {
                title: "On hover"
                SettingsRow {
                    label: "Music at rest"; detail: "Tiny art and bars beside the island while something plays"
                    Toggle { on: Settings.restMedia; onToggled: Settings.set("restMedia", !Settings.restMedia) }
                }
                SettingsRow {
                    label: "Weather"; detail: "In the island, for " + (Settings.weatherLocation || "where you are") + "  ·  rice set weatherLocation \"City\""
                    Toggle { on: Settings.restWeather; onToggled: Settings.set("restWeather", !Settings.restWeather) }
                }
                SettingsRow {
                    label: "Now playing"; detail: "The media card under the clock"
                    Toggle { on: Settings.hoverMedia; onToggled: Settings.set("hoverMedia", !Settings.hoverMedia) }
                }
                SettingsRow {
                    label: "Hover delay"; detail: "How long the pointer rests before the island grows"
                    Segmented {
                        options: [0, 120, 220, 400].map(n => ({ id: String(n), label: n ? n + " ms" : "None" }))
                        current: String(Settings.hoverDelay)
                        onPicked: id => Settings.set("hoverDelay", Number(id))
                    }
                }
            }
            SettingsGroup {
                title: "Kitty"
                SettingsRow {
                    label: "Tabs beside kitty"
                    detail: "A glass column of this window's tabs, on the left, while kitty is focused. Off until you turn it on."
                    Toggle { on: Settings.kittyTabs; onToggled: Settings.set("kittyTabs", !Settings.kittyTabs) }
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
                    label: "24-hour time"
                    Toggle { on: Settings.clock24; onToggled: Settings.set("clock24", !Settings.clock24) }
                }
                SettingsRow {
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
                    label: "Where they appear"
                    detail: Settings.notifSurface === "both" ? "In the island and as a toast" : "One place each: urgent, warnings and replies in the island; the rest as a toast; low ones only in the center"
                    Segmented {
                        options: [{ id: "one", label: "One place" }, { id: "both", label: "Both" }]
                        current: Settings.notifSurface
                        onPicked: id => Settings.set("notifSurface", id)
                    }
                }
                SettingsRow {
                    label: "Hide sensitive message text"
                    detail: Settings.notifRedactSensitive ? "Chat/mail: show who, not the body, until you Open" : "Full text on peek, toasts and center"
                    Toggle {
                        on: Settings.notifRedactSensitive
                        onToggled: Settings.set("notifRedactSensitive", !Settings.notifRedactSensitive)
                    }
                }
                SettingsRow {
                    label: "Toast opens on first click"
                    detail: Settings.notifToastInstantOpen ? "Tap a toast to open or run its default action" : "Tap to preview, then Open (center and island peek stay explicit)"
                    Toggle {
                        on: Settings.notifToastInstantOpen
                        onToggled: Settings.set("notifToastInstantOpen", !Settings.notifToastInstantOpen)
                    }
                }
                SettingsRow {
                    label: "Reply when toast opens"
                    detail: Settings.notifEngageReply ? "Engaging a replyable toast focuses the reply field" : "Show Open and Reply chips first"
                    Toggle {
                        on: Settings.notifEngageReply
                        onToggled: Settings.set("notifEngageReply", !Settings.notifEngageReply)
                    }
                }
                SettingsRow {
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
            SettingsGroup {
                SettingsRow {
                    label: "Who handles idle"; detail: Settings.idleOwner === "shell" ? "The shell: dims, fades, locks and sleeps, aware of Caffeine and of music playing" : "hypridle (~/.config/hypr/hypridle.conf); the rows below don't apply"
                    Segmented {
                        options: [{ id: "shell", label: "Shell" }, { id: "hypridle", label: "hypridle" }]
                        current: Settings.idleOwner
                        onPicked: id => Settings.set("idleOwner", id)
                    }
                }
                SettingsRow {
                    label: "Don't sleep while music plays"
                    Toggle { on: Settings.idleNoSleepWhilePlaying; onToggled: Settings.set("idleNoSleepWhilePlaying", !Settings.idleNoSleepWhilePlaying) }
                }
            }
            SettingsGroup {
                title: "On power"
                opacity: Settings.idleOwner === "shell" ? 1 : 0.45
                SettingsRow { label: "Dim the screen"; SecondsChoice { key: "idleDimAc"; values: [120, 240, 600, 0] } }
                SettingsRow { label: "Lock"; SecondsChoice { key: "idleLockAc"; values: [180, 300, 900, 0] } }
                SettingsRow { label: "Screen off"; SecondsChoice { key: "idleOffAc"; values: [330, 600, 1800, 0] } }
                SettingsRow { label: "Sleep"; SecondsChoice { key: "idleSleepAc"; values: [1800, 3600, 0] } }
            }
            SettingsGroup {
                title: "On battery"
                opacity: Settings.idleOwner === "shell" ? 1 : 0.45
                SettingsRow { label: "Dim the screen"; SecondsChoice { key: "idleDimBattery"; values: [60, 120, 300, 0] } }
                SettingsRow { label: "Lock"; SecondsChoice { key: "idleLockBattery"; values: [120, 180, 600, 0] } }
                SettingsRow { label: "Screen off"; SecondsChoice { key: "idleOffBattery"; values: [210, 300, 900, 0] } }
                SettingsRow { label: "Sleep"; SecondsChoice { key: "idleSleepBattery"; values: [600, 900, 1800, 0] } }
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
                    label: "Show the screensaver"
                    detail: Settings.screensaverWhen === "caffeine" ? "While Caffeine keeps the screen on, after a while of no input" : Settings.screensaverWhen === "always" ? "Whenever you're away, before the lock" : "Never"
                    Segmented {
                        options: [{ id: "caffeine", label: "With Caffeine" }, { id: "always", label: "Always" }, { id: "off", label: "Off" }]
                        current: Settings.screensaverWhen
                        onPicked: id => Settings.set("screensaverWhen", id)
                    }
                }
                SettingsRow {
                    label: "After"
                    Segmented {
                        options: [1, 3, 5, 10].map(n => ({ id: String(n), label: n + " min" }))
                        current: String(Settings.screensaverMins)
                        onPicked: id => Settings.set("screensaverMins", Number(id))
                    }
                }
                SettingsRow {
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
                    label: "Check every"; detail: Settings.updatesCheckHours > 0 ? Settings.updatesCheckHours + (Settings.updatesCheckHours === 1 ? " hour" : " hours") + " (needs no password)" : "Only when you open Software Update"
                    Segmented {
                        options: [{ id: "0", label: "Never" }, { id: "1", label: "1 h" }, { id: "3", label: "3 h" }, { id: "12", label: "12 h" }]
                        current: String(Settings.updatesCheckHours)
                        onPicked: id => Settings.set("updatesCheckHours", parseInt(id))
                    }
                }
                SettingsRow {
                    label: "Say when updates appear"; detail: "A short note from the island when there are new ones"
                    Toggle { on: Settings.updatesAnnounce; onToggled: Settings.set("updatesAnnounce", !Settings.updatesAnnounce) }
                }
                SettingsRow {
                    label: "Include Flatpak apps"; detail: "Sandboxed and signed; your own installs need no password"
                    Toggle { on: Settings.updatesFlatpak; onToggled: Settings.set("updatesFlatpak", !Settings.updatesFlatpak) }
                }
            }
            SettingsGroup {
                title: "AUR"
                SettingsRow {
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
                    label: "Restart the shell"; detail: "Reloads everything; notifications stay"
                    PillButton { text: "Restart"; onClicked: Quickshell.execDetached([settings.rice, "restart"]) }
                }
            }
        }
    }
}
