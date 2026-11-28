// Text whose changed characters morph (Skiper UI's animated text): the old
// glyph lifts and blurs away while the new one rises out of a blur into
// place, character by character with a small stagger. Unchanged characters
// stay still, so 23:27 → 23:28 moves one digit. Digits are tabular, so the
// width never jumps. Reduced motion: characters just change.
//
//   TextMorph { text: Dates.clock(now); size: 40; weight: Theme.wSemibold }
import QtQuick
import QtQuick.Effects
import qs.config

Row {
    id: morph

    property string text
    property int size: Theme.tCallout
    property int weight: Theme.wSemibold
    property color color: Theme.textPrimary
    property bool rounded: true
    property bool clockFace: false
    property int duration: Theme.morphMs         // per character
    property int stagger: 45
    // The cells are the digits' cap height, their baseline the cell's bottom:
    // `anchors.baseline` lines other text up with the digits.
    baselineOffset: height

    Repeater {
        model: morph.text.length
        Item {
            id: cell
            required property int index
            readonly property string ch: morph.text.charAt(index)
            property string was: ch
            property real t: 1           // 0 → 1 while changing
            width: Math.ceil(metrics.advanceWidth)
            // The cell is the cap height, so a row centres the digits
            // themselves (not their line box with its empty descender).
            height: Math.round(capH)
            // A digit's height above the baseline (QML's FontMetrics has no
            // capHeight): from the tight box of "0".
            readonly property real capH: digit.tightBoundingRect.height || caps.ascent * 0.72
            TextMetrics {
                id: digit
                text: "0"
                font.family: morph.clockFace ? Fonts.clockFace : morph.rounded ? Theme.roundedFamily(morph.weight) : Theme.textFamily(morph.weight)
                font.pixelSize: Math.round(morph.size * Theme.textScale)   // as Label sets it
                font.weight: morph.weight
                font.variableAxes: Theme.axesWeight(morph.size, morph.weight)
            }
            clip: false
            FontMetrics {
                id: caps
                font.family: morph.clockFace ? Fonts.clockFace : morph.rounded ? Theme.roundedFamily(morph.weight) : Theme.textFamily(morph.weight)
                font.pixelSize: Math.round(morph.size * Theme.textScale)   // as Label sets it
                font.weight: morph.weight
                font.variableAxes: Theme.axesWeight(morph.size, morph.weight)
            }
            readonly property real lift: -Math.round(caps.ascent - capH)

            TextMetrics {
                id: metrics
                text: /\d/.test(cell.ch) ? "0" : cell.ch
                font.family: morph.clockFace ? Fonts.clockFace : morph.rounded ? Theme.roundedFamily(morph.weight) : Theme.textFamily(morph.weight)
                font.pixelSize: Math.round(morph.size * Theme.textScale)   // as Label sets it
                font.weight: morph.weight
                font.features: Theme.numeralFeatures(morph.rounded, true)
                font.variableAxes: Theme.axesWeight(morph.size, morph.weight)
            }

            onChChanged: {
                if (Theme.reduceMotion || !morph.visible) { was = ch; t = 1; return; }
                run.stop();
                delay.duration = cell.index * morph.stagger;
                run.start();
            }
            SequentialAnimation {
                id: run
                PropertyAction { target: cell; property: "t"; value: 0 }
                PauseAnimation { id: delay; duration: cell.index * morph.stagger }
                NumberAnimation { target: cell; property: "t"; from: 0; to: 1; duration: morph.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                ScriptAction { script: cell.was = cell.ch }
            }

            // Leaving: up, fading, blurring.
            Label {
                id: oldGlyph
                visible: cell.t < 1 && cell.was !== cell.ch
                anchors.horizontalCenter: parent.horizontalCenter
                y: cell.lift - cell.height * 0.9 * cell.t
                opacity: 1 - cell.t
                text: cell.was
                size: morph.size; weight: morph.weight; rounded: morph.rounded; color: morph.color
                font.family: morph.clockFace ? Fonts.clockFace : morph.rounded ? Theme.roundedFamily(morph.weight) : Theme.textFamily(morph.weight)
                font.letterSpacing: morph.clockFace ? Fonts.clockTracking(morph.size) : Theme.tracking(morph.size, morph.rounded)
                font.features: Theme.numeralFeatures(morph.rounded, true)
                layer.enabled: visible
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: Math.min(1, cell.t * 1.4) }
            }
            // Arriving: from below, out of a blur.
            Label {
                id: newGlyph
                anchors.horizontalCenter: parent.horizontalCenter
                y: cell.lift + cell.height * 0.9 * (1 - cell.t)
                opacity: Math.min(1, cell.t * 1.6)
                text: cell.ch
                size: morph.size; weight: morph.weight; rounded: morph.rounded; color: morph.color
                font.family: morph.clockFace ? Fonts.clockFace : morph.rounded ? Theme.roundedFamily(morph.weight) : Theme.textFamily(morph.weight)
                font.letterSpacing: morph.clockFace ? Fonts.clockTracking(morph.size) : Theme.tracking(morph.size, morph.rounded)
                font.features: Theme.numeralFeatures(morph.rounded, true)
                layer.enabled: cell.t < 1
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: Math.max(0, 1 - cell.t * 1.5) }
            }
        }
    }
}
