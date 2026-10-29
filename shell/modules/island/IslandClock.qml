// The island's clock: hours and minutes roll digit by digit when they change
// (RollingNumber, after Skiper's animated number). 24h or 12h from Settings.
import QtQuick
import qs.config
import qs.components

Row {
    id: clock
    required property date now
    property int size: 14
    property color color: Theme.textPrimary

    RollingNumber {
        value: Settings.clock24 ? clock.now.getHours() : ((clock.now.getHours() + 11) % 12 + 1)
        pad: Settings.clock24 ? 2 : 1
        size: clock.size; weight: Theme.wSemibold; color: clock.color
    }
    Label { text: ":"; size: clock.size; weight: Theme.wSemibold; rounded: true; color: clock.color }
    RollingNumber {
        value: clock.now.getMinutes()
        pad: 2
        size: clock.size; weight: Theme.wSemibold; color: clock.color
    }
    Label {
        visible: Settings.showSeconds
        text: ":"; size: clock.size; weight: Theme.wSemibold; rounded: true; color: clock.color
    }
    RollingNumber {
        visible: Settings.showSeconds
        value: clock.now.getSeconds()
        pad: 2
        size: clock.size; weight: Theme.wSemibold; color: Theme.textSecondary
    }
}
