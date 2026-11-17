// "Borealis": the screensaver's second drawn scene (no video to decode). Curtains of light
// in the theme's own accent (and a hue either side of it) hang over a near-black sky and two
// ridges, with a slow scatter of stars. Switch theme and the sky changes colour with it.
//
// Cost: each curtain is a fan of soft rays drawn once into a texture (blurred once); what
// moves is that texture's offset and brightness, nothing is redrawn. The stars are one small
// particle system. Reduced motion: the still scene, no particles.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Particles
import qs.config

Item {
    id: scene
    property bool running: true
    property bool soft: true             // blur each curtain once (off: crisp rays, for a quick look in a window that can't draw effects)
    readonly property bool moving: running && !Theme.reduceMotion
    readonly property url assets: Qt.resolvedUrl("../../assets/screensaver/")
    readonly property var pal: Theme.borealisPalette
    clip: true

    // The accent, shifted round the colour wheel and kept vivid (a grey accent has no hue).
    function tone(shift, light) {
        const a = Theme.accent;
        const h = a.hslHue >= 0 ? a.hslHue : Theme.borealisFallbackHue;
        return Qt.hsla((h + shift + 1) % 1, Math.max(a.hslSaturation, Theme.borealisMinSat), light, 1);
    }

    // ── Sky ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: scene.pal.sky[0] }
            GradientStop { position: 0.55; color: scene.pal.sky[1] }
            GradientStop { position: 1.0; color: scene.pal.sky[2] }
        }
    }

    // ── Stars ────────────────────────────────────────────────────────────
    ParticleSystem { id: starSys; running: scene.moving; paused: !scene.moving }
    ImageParticle {
        system: starSys; groups: ["star"]
        source: scene.assets + "star.png"
        color: scene.pal.star; colorVariation: 0.08
        alpha: 0.9; alphaVariation: 0.5
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        system: starSys; group: "star"
        width: scene.width; height: scene.height * 0.62
        emitRate: 5; lifeSpan: 10000; lifeSpanVariation: 4000
        maximumEmitted: 60
        size: Theme.borealisStarSize; sizeVariation: 3
        startTime: 10000
    }

    // ── Curtains ─────────────────────────────────────────────────────────
    // x, y, w: where it hangs (fractions of the screen); shift: hue offset; light: its lightness;
    // seed: its own fold; alpha: how bright; sway: how far it drifts (fraction of its width).
    Repeater {
        model: [
            { x: 0.02, y: 0.06, w: 0.78, shift: 0.00, light: 0.55, seed: 1.3, alpha: 0.80, sway: 0.07, rate: 1.00 },
            { x: 0.30, y: 0.12, w: 0.70, shift: 0.09, light: 0.52, seed: 4.1, alpha: 0.60, sway: 0.09, rate: 1.35 },
            { x: 0.12, y: 0.02, w: 0.60, shift: -0.08, light: 0.50, seed: 7.7, alpha: 0.45, sway: 0.06, rate: 0.80 }
        ]
        delegate: Item {
            id: cur
            required property var modelData
            readonly property color col: scene.tone(modelData.shift, modelData.light)
            x: scene.width * modelData.x
            y: scene.height * modelData.y
            width: scene.width * modelData.w
            height: scene.height * 0.64
            opacity: modelData.alpha * pulse
            property real pulse: 1
            property real drift: 0
            transform: Translate { x: cur.drift * cur.width * cur.modelData.sway }
            layer.enabled: scene.soft
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.4; blurMax: 40 }

            Repeater {
                model: Theme.borealisRays
                delegate: Rectangle {
                    id: ray
                    required property int index
                    readonly property real t: index / (Theme.borealisRays - 1)
                    // A stable pseudo-random 0…1 per ray; a curtain folds along a slow wave and
                    // tapers to nothing at both ends.
                    readonly property real r: Math.abs(Math.sin(index * 12.9898 + cur.modelData.seed * 78.233))
                    readonly property real taper: Math.sin(t * Math.PI)
                    readonly property real baseY: cur.height * (0.80 + 0.09 * Math.sin(t * 6.4 + cur.modelData.seed))
                    x: t * (cur.width - width)
                    width: cur.width / Theme.borealisRays * 3.2
                    height: cur.height * (0.28 + 0.6 * r) * Math.pow(taper, 0.7)
                    y: baseY - height
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(cur.col, 0) }
                        GradientStop { position: 0.55; color: Qt.alpha(cur.col, 0.10) }
                        GradientStop { position: 0.90; color: Qt.alpha(cur.col, 0.50) }
                        GradientStop { position: 1.0; color: Qt.alpha(cur.col, 0) }
                    }
                }
            }

            // Drift to one side and back; breathe. Each curtain on its own beat.
            SequentialAnimation on drift {
                running: scene.moving; loops: Animation.Infinite
                NumberAnimation { from: -1; to: 1; duration: Theme.borealisSwayMs / cur.modelData.rate; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: -1; duration: Theme.borealisSwayMs / cur.modelData.rate; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on pulse {
                running: scene.moving; loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.55; duration: Theme.borealisPulseMs / cur.modelData.rate; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.55; to: 1; duration: Theme.borealisPulseMs / cur.modelData.rate; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── Ridges, drawn once ───────────────────────────────────────────────
    component Ridge: Shape {
        id: ridge
        property color fill
        property color rim: "transparent"
        property real base: 0.8          // where it stands (fraction of the height)
        property real rise: 0.08         // how tall the peaks are
        property real seed: 0
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        function points() {
            const n = 48, out = [];
            for (let i = 0; i <= n; i++) {
                const t = i / n;
                const y = base - rise * (0.55 * Math.sin(t * 5.1 + seed) + 0.3 * Math.sin(t * 12.7 + seed * 2) + 0.15 * Math.sin(t * 29 + seed * 3));
                out.push(Qt.point(t * width, y * height));
            }
            out.push(Qt.point(width, height)); out.push(Qt.point(0, height));
            return out;
        }
        ShapePath {
            fillColor: ridge.fill
            strokeColor: ridge.rim
            strokeWidth: ridge.rim.a > 0 ? 1 : 0
            PathPolyline { path: ridge.points() }
        }
    }
    Ridge { fill: scene.pal.farRidge; rim: scene.pal.rim; base: 0.86; rise: 0.10; seed: 2.2 }
    Ridge { fill: scene.pal.ridge; base: 0.93; rise: 0.07; seed: 5.9 }
}
