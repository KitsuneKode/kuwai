import QtQuick
import Quickshell.Io

QtObject {
    id: loader
    property string styleFile: ""
    property var config: ({})
    function customQmlUrl() {
        const c = String(loader.config.custom_qml || "");
        return !c ? "" : c.indexOf("file://") === 0 ? c : "file://" + c;
    }
    property FileView file: FileView {
        path: loader.styleFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { loader.config = JSON.parse(text() || "{}"); } catch (e) {} }
    }
}
