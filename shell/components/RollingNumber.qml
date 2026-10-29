// A number whose digits roll like an odometer when it changes: motion
// primitives' Sliding Number (refs/motion-primitives/sliding-number.tsx).
// Each digit is a column of 0–9 riding its own spring (their stiffness 280,
// damping 18, mass 0.3, here per unit mass); a digit takes the short way
// round (9 → 0 rolls on, not back through 8…1). Tabular figures, so the
// width never jumps. Reduced motion: digits just change.
//
//   RollingNumber { value: 64; suffix: "%"; size: 13; weight: Theme.wSemibold }
//   RollingNumber { value: minutes; pad: 2 }                       // "09"
import QtQuick
import qs.config

Row {
    id: num

    property real value: 0
    property string suffix
    property int size: 13
    property int weight: Theme.wRegular
    property color color: Theme.textPrimary
    property bool rounded: true
    // At least this many digits, zero-padded ("09" for minutes).
    property int pad: 1

    readonly property string digits: String(Math.max(0, Math.round(value))).padStart(pad, "0")
    readonly property var spring: ({ stiffness: 933, damping: 60 })

    TextMetrics {
        id: zero
        text: "0"
        font.family: num.rounded ? Theme.fontRounded : Theme.fontText
        font.pixelSize: num.size
        font.features: ({ "tnum": 1 })
        font.variableAxes: ({ "wght": num.weight })
    }

    Repeater {
        model: num.digits.length
        Item {
            id: col
            required property int index
            readonly property int digit: Number(num.digits.charAt(index))
            width: Math.ceil(zero.advanceWidth)
            height: Math.ceil(zero.height)
            clip: true

            Spring {
                id: roll
                tier: num.spring
                epsilon: 0.002
                target: col.digit
                Component.onCompleted: settle()
            }
            Connections {
                target: Theme
                function onReduceMotionChanged() { if (Theme.reduceMotion) roll.settle(); }
            }
            onDigitChanged: if (Theme.reduceMotion) roll.settle()

            Repeater {
                model: 10
                Label {
                    required property int index
                    // Distance from the rolling value, wrapped so each digit
                    // sits within five places above or below.
                    readonly property real off: ((10 + index - roll.value) % 10 + 10) % 10
                    y: (off > 5 ? off - 10 : off) * col.height
                    visible: Math.abs(y) < col.height
                    text: String(index)
                    size: num.size
                    weight: num.weight
                    rounded: num.rounded
                    color: num.color
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }
    Label {
        visible: num.suffix !== ""
        text: num.suffix
        size: num.size
        weight: num.weight
        rounded: num.rounded
        color: num.color
    }
}
