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

    readonly property string rice: Quickshell.env("HOME") + "/Projects/rice/bin/rice"
    readonly property var sections: [
        { id: "bar", label: "Bar & Island", glyph: "\u{f0d6f}", tint: "#0a84ff" },
        { id: "clock", label: "Clock & Date", glyph: "\u{f0954}", tint: "#ff9f0a" },
        { id: "notifs", label: "Notifications", glyph: "\u{f009a}", tint: "#ff453a" },
        { id: "motion", label: "Motion", glyph: "\u{f0e7d}", tint: "#bf5af2" },
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
                sourceComponent: [barPage, clockPage, notifPage, motionPage, aboutPage][settings.current]
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
