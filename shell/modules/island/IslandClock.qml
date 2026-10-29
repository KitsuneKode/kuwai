// The island's clock: when the minute turns, only the digits that change
// morph (TextMorph: up and out through a blur, the new one rising in), as in
// Skiper UI's animated text. 24h or 12h, seconds optional, from Settings.
import QtQuick
import qs.config
import qs.components

TextMorph {
    id: clock
    required property date now
    readonly property int h: Settings.clock24 ? now.getHours() : ((now.getHours() + 11) % 12 + 1)
    readonly property string hh: Settings.clock24 ? String(h).padStart(2, "0") : String(h)
    text: hh + ":" + String(now.getMinutes()).padStart(2, "0") + (Settings.showSeconds ? ":" + String(now.getSeconds()).padStart(2, "0") : "")
    weight: Theme.wSemibold
}
