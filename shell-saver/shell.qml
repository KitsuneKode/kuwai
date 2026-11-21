import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property string file: Quickshell.env("KUWAI_SAVER_FILE") || ""
    readonly property string want: Quickshell.env("KUWAI_SAVER_SCREEN") || ""
    Component.onCompleted: if (file === "") Qt.quit()

    Variants {
        model: Quickshell.screens.filter(s => root.want === "*" ? true : root.want === "" ? s === Quickshell.screens[0] : s.name === root.want)
        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "kuwai.saver-film"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            color: "black"

            VideoOutput {
                id: out
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                opacity: 0
                NumberAnimation on opacity { id: fadeIn; running: false; to: 1; duration: 1200; easing.type: Easing.OutCubic }
            }
            MediaPlayer {
                source: "file://" + encodeURI(root.file).replace(/#/g, "%23").replace(/\?/g, "%3F")
                activeAudioTrack: -1
                videoOutput: out
                loops: MediaPlayer.Infinite
                Component.onCompleted: play()
                onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) fadeIn.start()
                onErrorOccurred: (error, msg) => { console.warn("saver film: " + msg); Qt.quit(); }
            }
        }
    }
}
