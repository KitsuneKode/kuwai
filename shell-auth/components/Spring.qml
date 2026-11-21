import QtQuick
import qs.config

QtObject {
    id: s

    property var tier: Theme.springModerate
    property real target: 0
    property real value: 0
    property real velocity: 0
    property real epsilon: 0.0005
    property bool settled: true

    onTargetChanged: settled = false

    function settle() {
        value = target;
        velocity = 0;
        settled = true;
    }

    function snap(v) {
        target = v;
        value = v;
        velocity = 0;
        settled = true;
    }

    function step(dt) {
        const k = tier.stiffness, c = tier.damping;
        let t = Math.min(dt, 0.05);
        let x = value, v = velocity;
        while (t > 0) {
            const h = Math.min(t, 0.002);
            v += (-k * (x - target) - c * v) * h;
            x += v * h;
            t -= h;
        }
        if (Math.abs(x - target) < epsilon && Math.abs(v) < epsilon * 20) {
            value = target;
            velocity = 0;
            settled = true;
        } else {
            value = x;
            velocity = v;
        }
    }

    readonly property FrameAnimation ticker: FrameAnimation {
        running: !s.settled
        onTriggered: s.step(frameTime)
    }
}
