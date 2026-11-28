// The island's clock: when the minute turns, only the digits that change
// morph (TextMorph: up and out through a blur, the new one rising in), as in
// Skiper UI's animated text. 24h or 12h, seconds optional, from Settings;
// the locale's digits and separator (config/Dates).
import QtQuick
import qs.config
import qs.components

TextMorph {
    id: clock
    required property date now
    text: Dates.clock(now, Settings.showSeconds)
    weight: Theme.wSemibold
    clockFace: true
}
