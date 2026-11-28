import QtQuick

Item {
    id: surface
    property var audio: null
    property var style: null
    property var screen: null
    property string daemonState: "idle"
    property bool osdSuppressed: false
    property bool activeOutput: true
    visible: false
    Loader { id: custom; source: surface.style ? surface.style.customQmlUrl() : "" }
    readonly property var item: custom.item
}
