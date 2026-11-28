import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.components.ui
import qs.services
import "../../services/dictation.mjs" as D
import "../../services/keychord.mjs" as KC

Column {
    id: page
    spacing: Theme.s4 + 2

    readonly property var report: Dictation.report
    readonly property var vox: report ? report.voxtype : null
    readonly property var sh: report ? report.shuush : null
    readonly property var cfg: vox && vox.config ? vox.config : ({})
    readonly property bool hasVox: !!vox && vox.installed === true
    readonly property bool hasShuush: !!sh && sh.installed === true
    readonly property bool reading: !Dictation.loaded
    readonly property real readAt: report && report.at ? report.at : Date.now()
    readonly property var run: D.status(report, Activities.voxState)
    readonly property color stateTone: run.tone === "ok" ? Theme.green : run.tone === "busy" ? Theme.orange : run.tone === "bad" ? Theme.red : Theme.textSecondary
    readonly property var last: D.lastTake(report ? report.last : null, readAt)
    readonly property var clean: D.cleanup(sh)
    readonly property var learn: D.learning(sh ? sh.learn : null)
    readonly property var speed: D.speed(sh ? sh.speed : null)
    readonly property var kept: D.delivered(sh ? sh.delivered : null)
    readonly property var binds: D.keys(KeyBinds.entries)
    readonly property var pills: D.pillChoices((Settings.schema.settings.find(e => e.key === "dictationPill") || {}).enum)

    Component.onCompleted: { Dictation.open(); KeyBinds.load(); }
    Component.onDestruction: Dictation.close()

    function studio(tab) { Apps.run(tab ? ["shuush", "studio", "--tab", tab] : ["shuush", "studio"]); }

    Notice {
        visible: Dictation.loaded && Dictation.failed
        glyph: "\u{f0026}"
        title: "Couldn't read how dictation is doing"
        detail: "Nothing was changed"
        action: "Try again"
        onActed: Dictation.load()
    }

    SettingsGroup {
        title: "Status"
        visible: !Dictation.failed
        SettingsRow {
            label: "Dictation"
            detail: page.reading ? "Looking…" : page.run.detail
            Chip { visible: !page.reading; text: page.run.chip; tone: page.stateTone }
        }
        SettingsRow {
            visible: page.hasVox && page.vox.engine !== ""
            label: "Engine"
            detail: page.hasVox ? D.engine(page.vox) : ""
        }
        SettingsRow {
            visible: page.hasVox && page.vox.model !== ""
            label: "Model"
            detail: page.hasVox ? [page.vox.model, D.model(page.vox)].filter(x => x).join(" · ") : ""
        }
        SettingsRow {
            visible: page.hasVox
            label: "Last take"
            detail: page.last.detail
        }
    }

    SettingsGroup {
        title: "Listening"
        visible: page.hasVox && page.vox.answered
        SettingsRow {
            visible: typeof page.cfg.warm === "number"
            label: "Keep the microphone warm"
            detail: "Open a few seconds after a take, so the next one catches its first word"
            Segmented {
                options: D.options([0, 3, 5], page.cfg.warm, n => n + " s")
                current: String(page.cfg.warm)
                onPicked: id => Dictation.choose("warm", Number(id))
            }
        }
        SettingsRow {
            visible: typeof page.cfg.tail === "number"
            label: "Listen after you let go"
            detail: "Keeps the microphone open this long after the key, for the end of the last word"
            Segmented {
                options: D.options([0, 200, 400, 600], page.cfg.tail, n => n + " ms")
                current: String(page.cfg.tail)
                onPicked: id => Dictation.choose("tail", Number(id))
            }
        }
        SettingsRow {
            visible: typeof page.cfg.queue === "boolean"
            label: "Queue takes"
            detail: "Start the next take while the last one is still being written; they arrive in order"
            Toggle { on: page.cfg.queue === true; label: "Queue takes"; onToggled: Dictation.choose("queue", page.cfg.queue !== true) }
        }
        SettingsRow {
            visible: typeof page.cfg.preedit === "boolean"
            label: "Words in the field as you speak"
            detail: "Shown in the field, not yet final, where the app allows it"
            Toggle { on: page.cfg.preedit === true; label: "Words in the field as you speak"; onToggled: Dictation.choose("preedit", page.cfg.preedit !== true) }
        }
        SettingsRow {
            visible: Dictation.restartNeeded || Dictation.restartWaiting
            label: "Restart dictation"
            detail: Dictation.restartWaiting ? "Restarts with these settings once the current take is written" : "These settings apply once dictation restarts; it takes a few seconds"
            Button {
                height: Theme.sp(30); size: Theme.tSub
                text: Dictation.restartWaiting ? "Waiting" : "Restart"
                enabled: !Dictation.restartWaiting && !Dictation.busy
                onClicked: Dictation.restart()
            }
        }
        SettingsRow {
            visible: Dictation.note !== ""
            label: Dictation.note
        }
    }

    SettingsGroup {
        title: "Words on screen"
        SettingsRow {
            key: "dictationPill"
            label: "Dictation words"
            detail: D.pillDetail(page.pills, Settings.dictationPill)
            Segmented {
                options: page.pills
                current: Settings.dictationPill
                onPicked: id => Settings.set("dictationPill", id)
            }
        }
    }

    SettingsGroup {
        title: "Cleanup"
        visible: !page.reading && !Dictation.failed
        SettingsRow {
            label: "Tidied by"
            detail: page.hasShuush ? page.clean.chain + ". " + page.clean.where : "Nothing is installed to tidy your words: they arrive as they were heard, and nothing learns your fixes or measures speed"
            Chip { visible: page.hasShuush; text: page.clean.local ? "This computer" : "Online"; tone: page.clean.local ? Theme.green : Theme.textSecondary }
        }
        SettingsRow {
            visible: page.hasShuush && page.sh.cleanup_ready === false
            label: "No service is ready"
            detail: "Takes arrive as they were heard until one is set up in Studio"
        }
        SettingsRow {
            visible: page.hasShuush
            label: "Offline only"
            detail: page.clean.offline ? "On: only this computer tidies your words" : "Off. Studio's settings turn it on and change the order"
        }
        SettingsRow {
            visible: page.hasShuush
            label: "Studio"
            detail: "History, corrections and vocabulary"
            Button { height: Theme.sp(30); size: Theme.tSub; text: "Open Studio"; onClicked: page.studio("") }
        }
    }

    SettingsGroup {
        title: "Learning"
        visible: page.hasShuush && !!page.sh.learn
        SettingsRow { label: "Corrections"; detail: page.learn.rules }
        SettingsRow { label: "Vocabulary"; detail: page.learn.vocab }
        SettingsRow {
            label: "To review"
            detail: page.learn.pending
            Button { height: Theme.sp(30); size: Theme.tSub; text: "Review in Studio"; onClicked: page.studio("corrections") }
        }
    }

    SettingsGroup {
        title: "Speed and reliability"
        visible: page.hasShuush
        SettingsRow {
            label: "Key up to text"
            detail: page.speed.detail
            Label { visible: page.speed.value !== ""; text: page.speed.value; size: Theme.tBody; weight: Theme.wSemibold; tabular: true; color: Theme.textSecondary }
        }
        SettingsRow {
            label: "Delivered"
            detail: page.kept.detail
            Label { visible: page.kept.value !== ""; text: page.kept.value; size: Theme.tBody; weight: Theme.wSemibold; tabular: true; color: Theme.textSecondary }
        }
    }

    SettingsGroup {
        title: "Shortcuts"
        SettingsRow {
            visible: page.binds.length === 0
            label: !KeyBinds.loaded ? "Reading your shortcuts…" : "No dictation shortcuts"
        }
        Repeater {
            model: page.binds
            SettingsRow {
                id: keyRow
                required property var modelData
                label: modelData.text
                detail: modelData.chords.length ? "" : "No shortcut"
                Repeater {
                    model: keyRow.modelData.chords
                    RowLayout {
                        id: chord
                        required property var modelData
                        required property int index
                        spacing: Theme.s1
                        Label { visible: chord.index > 0; text: "or"; size: Theme.tFootnote; color: Theme.textTertiary }
                        Repeater {
                            model: KC.caps(chord.modelData)
                            KeyCap { required property var modelData; text: modelData }
                        }
                    }
                }
            }
        }
        SettingsRow {
            label: "Change them"
            detail: "In Shortcuts, with the rest of the desktop's keys"
            Button { height: Theme.sp(30); size: Theme.tSub; text: "Shortcuts"; onClicked: Island.settingsPage = "shortcuts" }
        }
    }
}
