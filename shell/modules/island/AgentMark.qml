import QtQuick
import qs.config
import qs.components
import qs.services
import "../../services/providers.mjs" as P

Item {
    id: am
    property string agent: ""
    property string name: ""
    property string model: ""
    property bool tiled: true
    property bool t3: false
    property color tint: Theme.wash(2)
    readonly property string vendor: {
        const v = P.vendorOf(model);
        const own = String(Kittymux.brand(agent)).replace(/^.*\//, "").replace(/\.svg$/, "");
        return v && v !== own ? v : "";
    }
    implicitWidth: Theme.sp(Theme.s5); implicitHeight: implicitWidth

    Image {
        id: tileImg
        anchors.fill: parent
        visible: am.tiled
        sourceSize: Qt.size(64, 64)
        source: am.tiled ? Kittymux.tile(am.agent) : ""
        smooth: true; mipmap: true
    }
    Rectangle {
        visible: !am.tiled || tileImg.status !== Image.Ready
        anchors.fill: parent
        radius: am.tiled ? Theme.r1 : width / 2
        color: am.tiled || markImg.status !== Image.Ready ? am.tint : "transparent"
        Image {
            id: markImg
            anchors.centerIn: parent
            width: am.tiled ? parent.width * 0.6 : parent.width; height: width
            sourceSize: Qt.size(64, 64)
            source: Kittymux.brand(am.agent)
            smooth: true; mipmap: true
        }
        Label {
            visible: markImg.status !== Image.Ready
            anchors.centerIn: parent
            text: P.monogram(am.name || am.agent)
            size: Theme.tCaption; weight: Theme.wSemibold
            color: Theme.textPrimary
        }
    }
    Rectangle {
        visible: am.vendor !== "" && vendorImg.status === Image.Ready
        anchors { right: parent.right; top: parent.top; rightMargin: -Theme.s1; topMargin: -Theme.s1 }
        width: Math.round(am.width * 0.5); height: width; radius: width / 2
        color: Theme.cutout
        Image {
            id: vendorImg
            anchors.centerIn: parent
            width: parent.width - Theme.s1; height: width
            sourceSize: Qt.size(32, 32)
            source: am.vendor ? Kittymux.brandDir + "/" + am.vendor + ".svg" : ""
            smooth: true; mipmap: true
        }
    }
    Rectangle {
        visible: am.t3 && t3Img.status === Image.Ready
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: -Theme.s1; bottomMargin: -Theme.s1 }
        width: Math.round(am.width * 0.53); height: width; radius: Theme.r1 - 3
        color: Theme.cutout
        Image {
            id: t3Img
            anchors.centerIn: parent
            width: parent.width - 3; height: width
            sourceSize: Qt.size(26, 26)
            source: am.t3 ? NotifAdapters.entryIcon("t3code") : ""
            smooth: true; mipmap: true
        }
    }
    Accessible.ignored: true
}
