import QtQuick
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services

Item {
    id: wp
    implicitWidth: Theme.panelS
    implicitHeight: Math.min(Theme.panelMaxH, col.implicitHeight + buttons.height + Theme.s4 + 40)

    property string shownMode: ""
    readonly property bool first: shownMode === "first"
    Component.onCompleted: shownMode = Welcome.mode || "new"
    Component.onDestruction: Welcome.markSeen()

    readonly property var chords: [
        { keys: ["Super", "A"], what: "Search: apps, files, settings, actions" },
        { keys: ["Super", "N"], what: "Notifications (or click the notch)" },
        { keys: ["Super", "V"], what: "Clipboard" },
        { keys: ["Super", "/"], what: "Every shortcut" }
    ]

    Flickable {
        id: flick
        x: 20; y: 20
        width: parent.width - 40
        height: parent.height - 40 - buttons.height - Theme.s4
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: col
            width: flick.width
            spacing: Theme.s4

            Column {
                width: parent.width
                spacing: 4
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: wp.first ? "Welcome to Kuwai" : "What's new in Kuwai " + Welcome.version
                    size: Theme.tTitle2; weight: Theme.wSemibold
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: wp.first ? "Four shortcuts reach most things. For the rest, click the notch or pull it down."
                                   : "kuwai has updated. Here is what changed; the changelog has the rest."
                    size: Theme.tSub; color: Theme.textSecondary
                }
            }

            Ui.Card {
                visible: wp.first
                spacing: Theme.s2
                Repeater {
                    model: wp.chords
                    Item {
                        required property var modelData
                        width: parent.width
                        height: Math.max(Theme.sp(28), what.implicitHeight)
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Repeater { model: modelData.keys; KeyCap { required property string modelData; text: modelData; size: Theme.tFootnote } }
                        }
                        Label {
                            id: what
                            anchors { left: parent.left; leftMargin: Theme.sp(92); right: parent.right; verticalCenter: parent.verticalCenter }
                            wrapMode: Text.Wrap
                            text: modelData.what
                            size: Theme.tBody
                        }
                    }
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Super is the key with the Windows logo."
                    size: Theme.tFootnote; color: Theme.textTertiary
                }
            }

            SettingsGroup {
                visible: wp.first
                title: "Running in the background, if you want them"
                SettingsRow {
                    label: "Clipboard history"
                    detail: "Text and images you copy, kept until you clear them"
                    Toggle { on: Welcome.collecting("clipboard"); onToggled: Welcome.setCollecting("clipboard", !on) }
                }
                SettingsRow {
                    label: "GitHub and Gmail"
                    detail: "GitHub through your gh sign-in; Gmail once you give it an app password (the README says how)"
                    Toggle { on: Welcome.collecting("feeds"); onToggled: Welcome.setCollecting("feeds", !on) }
                }
            }

            Column {
                visible: !wp.first
                width: parent.width
                spacing: Theme.s2
                Repeater {
                    model: Welcome.notes
                    Item {
                        required property var modelData
                        width: parent.width
                        height: note.implicitHeight
                        Label { text: "•"; size: Theme.tBody; color: Theme.textTertiary }
                        Label {
                            id: note
                            anchors { left: parent.left; leftMargin: Theme.s4; right: parent.right }
                            wrapMode: Text.Wrap
                            text: modelData.text
                            size: Theme.tBody
                        }
                    }
                }
                Label {
                    visible: Welcome.notes.length === 0
                    text: "No notes for this version."
                    size: Theme.tSub; color: Theme.textTertiary
                }
            }
        }
    }
    ScrollFade { flickable: flick }

    Row {
        id: buttons
        anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 20 }
        spacing: Theme.s2
        Ui.Button {
            text: wp.first ? "All shortcuts" : "Full changelog"
            onClicked: wp.first ? Island.open("keys", Island.screen, "pointer")
                                : Apps.open("https://github.com/KitsuneKode/kuwai/blob/main/CHANGELOG.md")
        }
        Ui.Button {
            primary: true
            text: "Done"
            onClicked: Island.close()
        }
    }
}
