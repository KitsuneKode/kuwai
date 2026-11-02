// VENDORED for the password prompt (shell-auth): a reviewed copy of
// shell/components/Spring.qml, not a link. Rule for everything in shell-auth/: read
// files and draw, nothing else — no Process, sockets, network or IPC here
// (`kuwai doctor` checks). Change the shell's copy freely; update this one
// on purpose (`kuwai auth diff` shows what drifted).
// A value that follows `target` like a damped spring. Retargeting keeps the
// current velocity, so a morph grabbed mid-flight turns around without a
// seam (Apple: interruptible, velocity-preserving; Fluid Functionalism: tiers).
// `snap(v)` assigns the target (breaking a binding on it); `settle()` doesn't.
//
//   Spring { id: p; tier: Theme.springSlow }   p.target = 1   →   p.value
//
// Integrated per frame (semi-implicit Euler in ≤2ms substeps, stable for the
// stiffest tier). `snap(v)` jumps without motion; `settled` is true at rest.
import QtQuick
import qs.config

QtObject {
    id: s

    property var tier: Theme.springModerate
    property real target: 0
    property real value: 0
    property real velocity: 0
    property real epsilon: 0.0005       // rest threshold, in the value's own units
    property bool settled: true

    onTargetChanged: settled = false

    // Jump to the current target without motion (keeps a bound target bound).
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
