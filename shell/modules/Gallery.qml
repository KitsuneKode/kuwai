// The design system on one sheet (docs/DESIGN.md): every primitive in
// components/ui and the shared controls, in their states. Shown by
// `qs ipc … call test gallery` for a screenshot; never takes the keyboard.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.components.ui

PanelWindow {
    id: win
    anchors { top: true; left: true }
    margins { top: 80; left: 80 }
    implicitWidth: 720
    implicitHeight: sheet.implicitHeight + 48
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "rice-gallery"

    Rectangle {
        anchors.fill: parent
        radius: Theme.r4
        color: "#1c1c1f"
        border.width: 1; border.color: Theme.cardEdge
    }
    Column {
        id: sheet
        x: 24; y: 24
        width: parent.width - 48
        spacing: Theme.s4

        Label { text: "Buttons"; size: 11; weight: Theme.wSemibold; color: Theme.textTertiary }
        Row {
            spacing: Theme.s3
            Button { text: "Update 31"; kind: "primary" }
            Button { text: "Keep mine"; kind: "secondary" }
            Button { text: "Remove"; kind: "danger" }
            Button { text: "Details"; kind: "quiet" }
            Button { text: "Disabled"; enabled: false }
        }
        Label { text: "Chips"; size: 11; weight: Theme.wSemibold; color: Theme.textTertiary }
        Row {
            spacing: Theme.s2
            Chip { text: "Security"; tone: Theme.red; glyph: "\u{f0483}" }
            Chip { text: "Needs you"; tone: Theme.orange }
            Chip { text: "Up to date"; tone: Theme.green }
            Chip { text: "AUR"; tone: Theme.textSecondary }
            Chip { text: "Selected"; tone: Theme.accent }
        }
        Label { text: "Notices"; size: 11; weight: Theme.wSemibold; color: Theme.textTertiary }
        Notice { glyph: "\u{f0026}"; title: "Reboot to finish"; detail: "The kernel changed (6.18 → 6.19). Your session stays as it is until then."; action: "Reboot"; tone: Theme.orange }
        Notice { glyph: "\u{f0159}"; title: "The update failed"; detail: "A mirror timed out. Nothing was changed."; tone: Theme.red }
        Notice { glyph: "\u{f012c}"; title: "Everything is up to date"; tone: Theme.green }
        Label { text: "Card · Meter · Tiles · Toggle"; size: 11; weight: Theme.wSemibold; color: Theme.textTertiary }
        Card {
            Meter { title: "Memory"; value: 0.62; detail: "9.8 of 16 GB" }
            Meter { title: "Disk"; value: 0.93; detail: "12 GB free" }
        }
        Row {
            spacing: Theme.s2
            Tile { glyph: "\u{f0176}"; label: "Caffeine"; on: true }
            Tile { glyph: "\u{f009b}"; label: "Focus"; on: false }
            Tile { glyph: "\u{f0594}"; label: "Night light"; on: false }
            Toggle { anchors.verticalCenter: parent.verticalCenter; on: true; label: "Example" }
            Toggle { anchors.verticalCenter: parent.verticalCenter; on: false; label: "Example" }
        }
    }
}
