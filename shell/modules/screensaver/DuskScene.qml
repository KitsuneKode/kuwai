// "Dusk": the screensaver's own scene, drawn live (no video to decode). An
// original evening in the hand-painted anime-film mood: a deep sky turning
// warm at the horizon, a moon with a soft halo, slow stars, three drifting
// clouds, layered hills with a little town whose windows come on one by one,
// the odd shooting star, and petals carried on the wind.
//
// Cost: the sky, moon, hills and town are drawn once and cached as textures
// (shapes keep their geometry; the halo and clouds are blurred once); what moves is a handful of transforms and two particle
// systems with small counts. Reduced motion: the still scene, no particles.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Particles
import qs.config

Item {
    id: scene
    property bool running: true
    readonly property bool moving: running && !Theme.reduceMotion
    readonly property url assets: Qt.resolvedUrl("../../assets/screensaver/")
    clip: true

    // ── Sky ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            // The warm band sits just above the hills (they start at ~66%).
            GradientStop { position: 0.00; color: "#0b1030" }
            GradientStop { position: 0.30; color: "#202862" }
            GradientStop { position: 0.48; color: "#4a3a7a" }
            GradientStop { position: 0.58; color: "#a35a82" }
            GradientStop { position: 0.65; color: "#f0937a" }
            GradientStop { position: 0.72; color: "#ffc98c" }
        }
    }

    // ── Stars: a slow twinkle, thinning towards the warm horizon ─────────
    ParticleSystem { id: starSys; running: scene.moving; paused: !scene.moving }
    ImageParticle {
        system: starSys; groups: ["star"]
        source: scene.assets + "star.png"
        color: "#fff6e8"; colorVariation: 0.08
        alpha: 0.9; alphaVariation: 0.5
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        system: starSys; group: "star"
        width: scene.width; height: scene.height * 0.5
        emitRate: 6; lifeSpan: 9000; lifeSpanVariation: 4000
        maximumEmitted: 70
        size: 5; sizeVariation: 4
        startTime: 9000
    }

    // ── Moon and its halo (drawn once) ────────────────────────────────────
    Item {
        id: moon
        x: scene.width * 0.72; y: scene.height * 0.13
        width: scene.height * 0.11; height: width
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 3.2; height: width; radius: width / 2
            color: "#fff0d8"; opacity: 0.10
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
        }
        Rectangle {
            anchors.fill: parent; radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: "#fffaf0" }
                GradientStop { position: 1; color: "#f6dcc0" }
            }
        }
    }

    // ── Clouds: three soft shapes, drifting a screen-width in minutes ────
    Repeater {
        model: [{ y: 0.24, w: 0.34, h: 0.05, o: 0.20, d: 180000, c: "#e9b8c8" },
                { y: 0.34, w: 0.46, h: 0.06, o: 0.16, d: 240000, c: "#d9a0b8" },
                { y: 0.18, w: 0.26, h: 0.035, o: 0.14, d: 300000, c: "#c8b8e8" }]
        Rectangle {
            id: cloud
            required property var modelData
            required property int index
            width: scene.width * modelData.w; height: scene.height * modelData.h
            radius: height / 2
            y: scene.height * modelData.y
            color: modelData.c; opacity: modelData.o
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 48 }
            x: -width + (scene.width + width) * ((index * 0.37) % 1)
            NumberAnimation on x {
                running: scene.moving
                from: -cloud.width; to: scene.width
                duration: cloud.modelData.d; loops: Animation.Infinite
            }
        }
    }

    // ── Shooting star, now and then ──────────────────────────────────────
    Rectangle {
        id: meteor
        width: scene.width * 0.12; height: 2; radius: 1
        rotation: 18; transformOrigin: Item.Right
        opacity: 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: "#fffbe8" }
        }
        SequentialAnimation {
            running: scene.moving; loops: Animation.Infinite
            PauseAnimation { duration: 14000 }
            ScriptAction { script: { meteor.x = scene.width * (0.15 + Math.random() * 0.5); meteor.y = scene.height * (0.05 + Math.random() * 0.2); } }
            ParallelAnimation {
                NumberAnimation { target: meteor; property: "opacity"; from: 0; to: 0.9; duration: 180 }
                NumberAnimation { target: meteor; property: "x"; to: meteor.x + scene.width * 0.16; duration: 900; easing.type: Easing.OutQuad }
                NumberAnimation { target: meteor; property: "y"; to: meteor.y + scene.height * 0.06; duration: 900; easing.type: Easing.OutQuad }
                SequentialAnimation { PauseAnimation { duration: 450 } NumberAnimation { target: meteor; property: "opacity"; to: 0; duration: 450 } }
            }
            PauseAnimation { duration: 9000 }
        }
    }

    // ── Hills and the town (drawn once) ──────────────────────────────────
    Item {
        id: land
        anchors.fill: parent
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {   // far hills
                fillColor: "#6a4a7e"; strokeColor: "transparent"
                startX: 0; startY: scene.height * 0.74
                PathCubic { x: scene.width * 0.45; y: scene.height * 0.70; control1X: scene.width * 0.15; control1Y: scene.height * 0.66; control2X: scene.width * 0.30; control2Y: scene.height * 0.74 }
                PathCubic { x: scene.width; y: scene.height * 0.68; control1X: scene.width * 0.65; control1Y: scene.height * 0.64; control2X: scene.width * 0.82; control2Y: scene.height * 0.73 }
                PathLine { x: scene.width; y: scene.height } PathLine { x: 0; y: scene.height }
            }
            ShapePath {   // middle hills
                fillColor: "#3d2c5a"; strokeColor: "transparent"
                startX: 0; startY: scene.height * 0.82
                PathCubic { x: scene.width * 0.55; y: scene.height * 0.80; control1X: scene.width * 0.2; control1Y: scene.height * 0.74; control2X: scene.width * 0.38; control2Y: scene.height * 0.84 }
                PathCubic { x: scene.width; y: scene.height * 0.77; control1X: scene.width * 0.72; control1Y: scene.height * 0.76; control2X: scene.width * 0.88; control2Y: scene.height * 0.82 }
                PathLine { x: scene.width; y: scene.height } PathLine { x: 0; y: scene.height }
            }
        }
        // The town on the middle ridge: simple blocks, a few windows lit.
        // Low houses with the odd taller block, irregular gaps, a pitched
        // roof on some: a town, not a bar chart.
        Repeater {
            model: 22
            Item {
                id: house
                required property int index
                readonly property real r: ((index * 7919) % 97) / 97
                readonly property real r2: ((index * 131) % 53) / 53
                readonly property bool tall: index % 7 === 3
                width: scene.width * (0.010 + r * 0.012)
                height: scene.height * (tall ? 0.06 + r2 * 0.03 : 0.018 + r2 * 0.022)
                x: scene.width * (0.50 + index * 0.0205 + r2 * 0.006)
                y: scene.height * (0.795 + 0.008 * Math.sin(index * 0.7)) - height
                Rectangle { anchors.fill: parent; color: "#2a1f42" }
                Shape {
                    visible: !house.tall && house.index % 2 === 0
                    width: parent.width; height: parent.width * 0.45
                    y: -height + 0.5
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "#2a1f42"; strokeColor: "transparent"
                        startX: 0; startY: house.width * 0.45
                        PathLine { x: house.width / 2; y: 0 }
                        PathLine { x: house.width; y: house.width * 0.45 }
                    }
                }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {   // near ground
                fillColor: "#160f26"; strokeColor: "transparent"
                startX: 0; startY: scene.height * 0.90
                PathCubic { x: scene.width; y: scene.height * 0.88; control1X: scene.width * 0.35; control1Y: scene.height * 0.85; control2X: scene.width * 0.7; control2Y: scene.height * 0.93 }
                PathLine { x: scene.width; y: scene.height } PathLine { x: 0; y: scene.height }
            }
        }
    }
    // Windows: lit at random, a few at a time.
    Repeater {
        model: 34
        Rectangle {
            id: win
            required property int index
            readonly property real r: ((index * 104729) % 89) / 89
            width: Math.max(2, scene.width * 0.0022); height: width * 1.3
            x: scene.width * (0.505 + r * 0.43)
            y: scene.height * (0.765 + ((index * 37) % 23) / 23 * 0.025)
            color: "#ffd38a"
            opacity: 0
            SequentialAnimation on opacity {
                running: scene.moving; loops: Animation.Infinite
                PauseAnimation { duration: 2000 + win.index * 900 % 17000 }
                NumberAnimation { to: 0.9; duration: 600 }
                PauseAnimation { duration: 12000 + win.r * 20000 }
                NumberAnimation { to: 0; duration: 900 }
            }
        }
    }

    // ── Petals on the wind ───────────────────────────────────────────────
    ParticleSystem { id: petalSys; running: scene.moving; paused: !scene.moving }
    ImageParticle {
        system: petalSys
        source: scene.assets + "petal.png"
        rotationVariation: 180; rotationVelocity: 40; rotationVelocityVariation: 60
        alpha: 0.85; alphaVariation: 0.2
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        system: petalSys
        x: -scene.width * 0.1; y: -40
        width: scene.width * 0.9; height: 10
        emitRate: 1.4; lifeSpan: 16000; lifeSpanVariation: 3000
        maximumEmitted: 28
        size: Math.round(scene.height * 0.012); sizeVariation: Math.round(scene.height * 0.006)
        velocity: AngleDirection { angle: 70; angleVariation: 15; magnitude: scene.height * 0.06; magnitudeVariation: scene.height * 0.03 }
    }
    Wander { system: petalSys; xVariance: scene.width * 0.08; pace: 60 }
}
