import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root
    property bool answered: false
    function finish(word) {
        console.log("PAM-RESULT " + word);
        Qt.quit();
    }
    PamContext {
        id: pam
        config: "login"
        user: Quickshell.env("KUWAI_PAM_USER")
        onPamMessage: {
            if (!responseRequired) return;
            if (root.answered) { root.finish("asked-twice"); return; }
            root.answered = true;
            respond(Quickshell.env("KUWAI_PAM_PASSWORD"));
        }
        onCompleted: result => root.finish(result === PamResult.Success ? "success" : "failed")
        onError: err => root.finish("error")
        Component.onCompleted: start()
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: root.finish("timeout")
    }
}
