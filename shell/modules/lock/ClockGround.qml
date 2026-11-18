// The ground under the lock screen's date and clock: as dark as that
// wallpaper needs, there and nowhere else.
//
// The clock is white and has no ground of its own; over a light wallpaper it
// was white on white (1.1:1 on a snow scene; 120 of 400 installed wallpapers
// put it under 3:1, measured by bin/kuwai-rehearse --wall). The comment said
// "lifted towards white so it reads on any wallpaper".
//
// This reads how bright the wallpaper is behind the clock (once per
// wallpaper, from a 32 x 18 copy) and lays a soft shade over the top of the
// screen, only as strong as it takes for the text to reach 3.2:1 there, and
// none at all over a dark picture. It falls away slowly below the clock and is
// gone by 72 % of the height, so the rest of the wallpaper keeps its own light. lib/rehearse/wall.py models the
// same rule; tests/ui/clock-ground.qml measures the real picture.
//
//   ClockGround { anchors.fill: parent; source: wall.source; ink: view.tint; base: 0.22 }
import QtQuick
import qs.config

Item {
    id: ground
    property url source
    property color ink: "white"
    property real base: 0.22            // the scrim already over the whole wallpaper
    readonly property real want: 3.5    // large text needs 3:1; over it, for the blur's unevenness
    readonly property real most: 0.62   // never darker than this: past it the wallpaper is gone
    // The clock's zone, as shares of the screen (LockView: the column starts at 11 % of the height).
    readonly property rect zone: Qt.rect(0.33, 0.10, 0.34, 0.20)
    // How bright it gets behind the clock (0-1, sRGB; what 95 % of the zone is under), and the shade for it.
    property real bright: 0
    property real shade: {
        const fg = Theme.luminance(Qt.rgba(ink.r, ink.g, ink.b, 1));
        // Find the least total darkening that reaches `want`; the base scrim counts.
        for (let s = base; s <= most + 0.001; s += 0.02) {
            const v = bright * (1 - s), bg = Theme.luminance(Qt.rgba(v, v, v, 1));
            if ((Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05) >= want) return Math.max(0, 1 - (1 - s) / (1 - base));
        }
        return 1 - (1 - most) / (1 - base);
    }
    Behavior on shade { NumberAnimation { duration: Theme.colorMs } }

    Rectangle {
        width: parent.width
        // Full to just under the clock, then a long fall: a vignette, not a band
        // with an edge (it ended in a sixth of the screen at first, and showed).
        height: Math.round(parent.height * 0.72)
        visible: ground.shade > 0.005
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, ground.shade) }
            GradientStop { position: 0.44; color: Qt.rgba(0, 0, 0, ground.shade) }
            GradientStop { position: 0.72; color: Qt.rgba(0, 0, 0, ground.shade * 0.4) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
        }
    }

    Canvas {
        id: probe
        width: 32; height: 18
        opacity: 0                       // painted (a hidden canvas is not), never seen
        renderStrategy: Canvas.Immediate
        property string held: ""
        function take() {
            const src = String(ground.source);
            if (held && held !== src) unloadImage(held);
            held = src;
            if (!src) { ground.bright = 0; return; }
            if (isImageLoaded(src)) requestPaint(); else loadImage(src);
        }
        onImageLoaded: requestPaint()
        onPaint: {
            if (!held || !isImageLoaded(held)) return;
            const ctx = getContext("2d");
            ctx.drawImage(held, 0, 0, width, height);
            const z = ground.zone;
            const d = ctx.getImageData(Math.floor(z.x * width), Math.floor(z.y * height),
                                       Math.max(1, Math.ceil(z.width * width)), Math.max(1, Math.ceil(z.height * height))).data;
            const tones = [];
            for (let i = 0; i < d.length; i += 4) tones.push(Math.max(d[i], d[i + 1], d[i + 2]) / 255);
            tones.sort((a, b) => a - b);
            ground.bright = tones.length ? tones[Math.min(tones.length - 1, Math.floor(tones.length * 0.95))] : 0;
        }
    }
    onSourceChanged: probe.take()
    Component.onCompleted: probe.take()
}
