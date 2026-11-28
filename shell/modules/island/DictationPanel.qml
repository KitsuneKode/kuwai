import QtQuick
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services

Item {
    id: panel

    readonly property string phase: DictationLive.phase
    readonly property bool live: DictationLive.live
    readonly property string app: DictationLive.app
    readonly property string full: DictationLive.fullText
    readonly property bool inField: DictationLive.fieldTake || Activities.voxInField
    readonly property string headline: {
        switch (phase) {
        case "listening": return "Listening";
        case "quiet": return "Too quiet to hear";
        case "muted": return "The mic is muted";
        case "silent-mic": return "No sound from the mic";
        case "writing": return "Writing it out";
        case "": return "Dictation";
        }
        return DictationLive.said;
    }
    readonly property string detail: {
        if (live) return (app ? "Into " + app + " · " : "") + DictationLive.clock;
        if (phase === "writing") return app ? "Into " + app : "";
        if (phase === "recovered") return (app ? "It was going into " + app + ". " : "") + "Bring it back to paste it where you are now.";
        if (phase === "quiet") return "Speak a little closer to the mic.";
        if (phase === "clipboard") return "The field didn’t take it, so it’s on the clipboard.";
        if (phase === "private") return "The field asked for privacy, so nothing was typed.";
        if (phase === "cancelled" || phase === "nothing") return "Nothing was typed.";
        if (phase === "silent" || phase === "silent-mic" || phase === "muted") return "Check the microphone in Sound.";
        if (phase === "failed") return "Nothing was typed. Try again in a moment.";
        if (phase === "untyped") return "The window didn’t take the text.";
        return "";
    }
    readonly property string emptyText: DictationLive.hidden ? (DictationLive.privateTake ? "A private field: its words never show here." : "Words are hidden while your screen is shared.")
        : inField ? "The words show in " + (app || "the field") + " as you speak."
        : live ? "Listening for your first words…"
        : phase === "writing" ? "Writing out what you said…"
        : ""

    implicitWidth: Theme.panelS
    implicitHeight: Math.min(Theme.panelMaxH, col.implicitHeight + Theme.s4 * 2)
    Accessible.role: Accessible.Pane
    Accessible.name: "Dictation"

    Column {
        id: col
        x: Theme.s4; y: Theme.s4
        width: parent.width - Theme.s4 * 2
        spacing: Theme.s3

        Row {
            width: parent.width
            spacing: Theme.s3
            DictationMark {
                id: lead
                lead: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - lead.width - parent.spacing
                spacing: 2
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: panel.headline
                    size: Theme.tTitle3; weight: Theme.wSemibold
                    color: panel.phase === "listening" || panel.phase === "writing" || panel.phase === "delivered" ? Theme.textPrimary : DictationLive.tone
                }
                Label {
                    visible: text !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: panel.detail
                    size: Theme.tSub
                    color: Theme.textSecondary
                    tabular: panel.live
                }
            }
        }

        Rectangle {
            visible: panel.full !== "" || panel.emptyText !== ""
            width: parent.width
            height: Math.min(Theme.sp(180), body.implicitHeight + Theme.s3 * 2)
            radius: Theme.r2
            color: Theme.card
            border.width: 1; border.color: Theme.cardEdge
            ScrollFade { flickable: words }
            ScrollHint { flickable: words; inside: true }
            Flickable {
                id: words
                x: Theme.s3; y: Theme.s3
                width: parent.width - Theme.s3 * 2
                height: parent.height - Theme.s3 * 2
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                function follow() { contentY = panel.live || panel.phase === "writing" ? Math.max(0, contentHeight - height) : 0; }
                onContentHeightChanged: follow()
                onHeightChanged: follow()
                Label {
                    id: body
                    width: words.width
                    wrapMode: Text.Wrap
                    text: panel.full !== "" ? panel.full : panel.emptyText
                    size: panel.full !== "" ? Theme.tCallout : Theme.tSub
                    color: panel.full !== "" ? Theme.textPrimary : Theme.textSecondary
                }
            }
        }

        Label {
            visible: DictationLive.queued > 0
            width: parent.width
            wrapMode: Text.Wrap
            text: DictationLive.queued === 1 ? "One more take is being written." : DictationLive.queued + " more takes are being written."
            size: Theme.tFootnote
            color: Theme.textTertiary
        }

        Row {
            visible: cancel.visible || finish.visible || bring.visible
            anchors.right: parent.right
            spacing: Theme.s2
            Ui.Button {
                id: cancel
                visible: panel.live || panel.phase === "writing"
                text: "Cancel"
                kind: "secondary"
                onClicked: DictationLive.cancel()
            }
            Ui.Button {
                id: finish
                visible: panel.live
                text: "Finish"
                kind: "primary"
                onClicked: DictationLive.finish()
            }
            Ui.Button {
                id: bring
                visible: panel.phase === "recovered" && !DictationLive.bringFailed
                text: "Bring back"
                kind: "primary"
                onClicked: DictationLive.bringBack()
            }
        }
    }
}
