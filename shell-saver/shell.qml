// The screensaver's film, in its own small process (the main shell's
// Screensaver.qml starts it while Night or Live shows, and SIGKILLs it when
// the screensaver goes). Measured: a video player costs ~190 MB while it
// plays and left ~110 MB behind for good inside the shell once it stopped;
// here the whole process ends, so all of it goes back.
//
// One screen (KUWAI_SAVER_SCREEN), on the Top layer: under the shell's own
// screensaver surface (Overlay: the clock, the input that dismisses), no
// keyboard, no input region. Any failure quits; the shell (which only ever kills it) then
// treats any exit as a failure and falls back to Dusk.
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
        model: Quickshell.screens.filter(s => root.want === "" ? s === Quickshell.screens[0] : s.name === root.want)
        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "rice-saver-film"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            color: "black"

            VideoOutput {
                id: out
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                opacity: 0
                // In once the first frames are up, as slowly as the shell's fade.
                NumberAnimation on opacity { id: fadeIn; running: false; to: 1; duration: 1200; easing.type: Easing.OutCubic }
            }
            MediaPlayer {
                source: "file://" + root.file
                videoOutput: out
                loops: MediaPlayer.Infinite
                Component.onCompleted: play()
                onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) fadeIn.start()
                onErrorOccurred: (error, msg) => { console.warn("saver film: " + msg); Qt.quit(); }
            }
        }
    }
}
