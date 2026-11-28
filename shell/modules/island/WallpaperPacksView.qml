import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.components.ui as Ui
import "../../services/sizes.mjs" as Sizes

Item {
    id: view
    implicitHeight: section.implicitHeight
    required property var packs
    required property string state
    required property string activePack
    required property string failedPack
    required property int done
    required property int total
    signal download(var pack)
    signal refresh()

    ColumnLayout {
        id: section
        anchors.fill: parent
        spacing: Theme.s3
        Label { text: "Wallpaper packs"; size: Theme.tTitle3; weight: Theme.wSemibold }
        RowLayout {
            visible: view.state !== "ready"
            Label {
                text: view.state === "error" ? "Couldn’t load wallpaper packs." : "Loading wallpaper packs…"
                color: Theme.textSecondary
                Accessible.role: Accessible.StatusBar
            }
            Ui.Button {
                visible: view.state === "error"
                text: "Try again"
                Layout.preferredHeight: implicitHeight
                onClicked: view.refresh()
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            visible: view.state === "ready"
            spacing: Theme.s2
            Repeater {
                model: view.packs
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool downloading: view.activePack === modelData.id
                    readonly property bool failed: view.failedPack === modelData.id
                    Layout.fillWidth: true
                    radius: Theme.r3
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.cardEdge
                    implicitHeight: detail.implicitHeight + Theme.s3 * 2

                    RowLayout {
                        id: detail
                        anchors { fill: parent; margins: Theme.s3 }
                        spacing: Theme.s3
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.s1
                            Label { text: card.modelData.name; size: Theme.tBody; weight: Theme.wSemibold }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: card.downloading
                                    ? "Downloading… " + view.done + " of " + view.total + " verified"
                                    : card.failed ? "Download failed."
                                    : card.modelData.images.length + " wallpapers · "
                                        + Sizes.bytes(card.modelData.images.reduce((sum, image) => sum + image.bytes, 0))
                                size: Theme.tSub
                                color: card.failed ? Theme.orange : Theme.textSecondary
                                font.features: Theme.featTabular
                                Accessible.role: Accessible.StatusBar
                            }
                        }
                        Label {
                            visible: !!card.modelData.installed
                            text: "Downloaded"
                            size: Theme.tSub
                            color: Theme.green
                        }
                        Ui.Button {
                            visible: !card.modelData.installed && !card.downloading
                            text: card.failed ? "Try again" : "Download"
                            enabled: !view.activePack
                            size: Theme.tSub
                            Layout.preferredHeight: implicitHeight
                            onClicked: view.download(card.modelData)
                        }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
