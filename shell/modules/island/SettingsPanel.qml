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
import qs.services

FocusScope {
    id: settings
    focus: true

    implicitWidth: 780
    implicitHeight: 520

    readonly property string rice: Paths.bin + "/rice"
    readonly property var sections: [
        { id: "bar", label: "Bar & Island", glyph: "\u{f0d6f}", tint: "#0a84ff" },
        { id: "clock", label: "Clock & Date", glyph: "\u{f0954}", tint: "#ff9f0a" },
        { id: "notifs", label: "Notifications", glyph: "\u{f009a}", tint: "#ff453a" },
        { id: "motion", label: "Motion", glyph: "\u{f0e7d}", tint: "#bf5af2" },
        { id: "island", label: "Island", glyph: "\u{f0d6f}", tint: "#ff9f0a" },
        { id: "workspaces", label: "Workspaces", glyph: "\u{f0570}", tint: "#5e5ce6" },
        { id: "clipboard", label: "Clipboard", glyph: "\u{f014c}", tint: "#64d2ff" },
        { id: "updates", label: "Software Update", glyph: "\u{f06b0}", tint: "#30d158" },
        { id: "about", label: "About", glyph: "\u{f02fd}", tint: "#8e8e93" }
    ]
    property int current: 0

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
                sourceComponent: [barPage, clockPage, notifPage, motionPage, islandRestPage, workspacesPage, clipboardPage, updatesPage, aboutPage][settings.current]
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
            }
            SettingsGroup {
                title: "On hover"
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
                    Toggle { on: Notifs.dnd; onToggled: Notifs.dnd = !Notifs.dnd }
                }
                SettingsRow {
                    label: "Clear seen notifications"; detail: "Ones you saw and didn't act on"
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
                    readonly property string style: Settings.islandTucked ? "hidden" : Settings.islandRest === "full" ? "full" : "minimal"
                    label: "Style"
                    detail: style === "hidden" ? "Out of the way: it appears near the top edge, with Ctrl+Alt+W, or when something needs you. Windows get the whole screen."
                          : style === "full" ? "Workspaces, time and status, always"
                          : "Just the time, or what's alive: music, a moment, a password, a recording. Near the top edge for the rest."
                    Segmented {
                        options: [{ id: "minimal", label: "Minimal" }, { id: "hidden", label: "Hidden" }, { id: "full", label: "Everything" }]
                        current: parent.style
                        onPicked: id => {
                            Settings.set("islandTucked", id === "hidden");
                            Settings.set("islandRest", id === "full" ? "full" : "minimal");
                        }
                    }
                }
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
