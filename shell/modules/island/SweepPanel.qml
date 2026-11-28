import QtQuick
import qs.config
import qs.services
import qs.components.ui as Ui

Ui.DeclarativePanel {
    id: panel
    model: Sweep.panel
    maxHeight: Math.min(Theme.panelMaxH, Theme.screenSize(Screen, "height", 1080) - Theme.s5) - Theme.s5 - Theme.s4 - Theme.sp(34)
    keyHints: Island.via === "key" && rows.length > 0 ? [["↑↓", "Project"], ["←→", "Part"], ["↵", "Review in Sweep"], ["esc", "Back"]] : []
    readonly property int dwellMs: 1500

    onIntent: (id, rowId, url) => {
        Sweep.markViewed();
        if (Sweep.act(id, rowId, url)) Island.close();
    }
    Keys.onReleased: e => { if (e.key !== Qt.Key_Escape) Sweep.markViewed(); }

    Component.onCompleted: {
        Sweep.opened(!Island.previewing);
        if (!Island.previewing) Sweep.markViewed();
    }
    Component.onDestruction: Sweep.closed()
    Connections {
        target: Island
        function onPreviewingChanged() { if (!Island.previewing && panel.visible) Sweep.opened(true); }
    }
    Timer { interval: panel.dwellMs; running: Island.previewing && panel.visible; onTriggered: Sweep.markViewed() }
}
