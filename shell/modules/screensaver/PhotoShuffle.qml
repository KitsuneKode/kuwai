import QtQuick
import qs.config
import "saverPhotos.mjs" as Photos

Item {
    id: shuffle

    property var paths: []
    property bool running: true
    property int holdMs: Photos.holdMs(5)
    property int seed: Math.floor(Math.random() * 4294967295)
    readonly property int side: Photos.decodeSide(width, height, 2560)

    readonly property var plan: Photos.order(paths.length, seed)
    readonly property int count: plan.length
    property int at: 0
    property bool aTop: true
    property real fade: 0
    property bool pending: false
    property var bad: ({})
    readonly property Image front: aTop ? imgA : imgB
    readonly property Image back: aTop ? imgB : imgA
    readonly property bool shown: front.status === Image.Ready

    function source(i) { return count > 0 ? Photos.fileUrl(paths[plan[((i % count) + count) % count]]) : ""; }
    function load(img, i) { img.idx = i; img.source = i >= 0 ? source(i) : ""; }
    function reset() {
        fadeAnim.stop();
        fade = 0; pending = false; bad = ({}); at = 0; aTop = true;
        load(imgA, count > 0 ? 0 : -1);
        load(imgB, count > 1 ? 1 : -1);
    }
    onPlanChanged: reset()
    Component.onCompleted: reset()

    function advance() {
        if (fadeAnim.running) return false;
        if (back.idx < 0 || back.status !== Image.Ready) { pending = back.idx >= 0; return false; }
        pending = false;
        fadeAnim.start();
        return true;
    }
    function landed() {
        at = back.idx;
        aTop = !aTop;
        fade = 0;
        load(back, Photos.after(at, count, bad));
    }
    function statusOf(img) {
        if (img.status === Image.Error) {
            const b = Object.assign({}, bad);
            b[img.idx] = true;
            bad = b;
            if (img === back) load(back, Photos.after(at, count, bad));
            else if (count > 1) pending = true;
        }
        if (pending && back.status === Image.Ready) advance();
    }

    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.ambientFadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Image {
        id: imgA
        property int idx: -1
        anchors.fill: parent
        z: shuffle.aTop ? 1 : 0
        opacity: shuffle.aTop ? 1 - shuffle.fade : 1
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(shuffle.side, shuffle.side)
        onStatusChanged: shuffle.statusOf(imgA)
    }
    Image {
        id: imgB
        property int idx: -1
        anchors.fill: parent
        z: shuffle.aTop ? 0 : 1
        opacity: shuffle.aTop ? 1 : 1 - shuffle.fade
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(shuffle.side, shuffle.side)
        onStatusChanged: shuffle.statusOf(imgB)
    }

    NumberAnimation {
        id: fadeAnim
        target: shuffle; property: "fade"; from: 0; to: 1
        duration: Theme.saverPhotoFadeMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut
        onFinished: shuffle.landed()
    }
    Timer {
        interval: shuffle.holdMs; repeat: true
        running: shuffle.running && shuffle.count > 1
        onTriggered: shuffle.advance()
    }
}
