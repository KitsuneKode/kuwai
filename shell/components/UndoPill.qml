// "Cleared 3 · Undo": the way back from a clear, on the surface that made it,
// for as long as Notifs holds the clear (Theme.undoMs; services/notifUndo.mjs).
// Click it, Space/Enter once Tab reaches it, or ⌃Z where its surface has the
// keyboard. It names a count only: never a title or a body.
//
//   UndoPill { surface: "island" }
import QtQuick
import qs.config
import qs.services
import qs.components.ui as Ui

Ui.Button {
    id: pill
    kind: "secondary"
    size: Theme.tSub
    required property string surface
    readonly property bool live: Notifs.undoSurface === surface && Notifs.undoLabel !== ""
    // Keeps its words while it fades (the label empties the moment it ends).
    property string said: ""
    onLiveChanged: if (live) said = Notifs.undoLabel
    Connections {
        target: Notifs
        function onUndoLabelChanged() { if (pill.live) pill.said = Notifs.undoLabel; }
    }

    text: said
    height: 24
    opacity: live ? 1 : 0
    visible: opacity > 0
    enabled: live
    Behavior on opacity { NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    onClicked: Notifs.undoClear()

    Accessible.name: Notifs.undoCount === 1 ? "Undo: bring back 1 cleared notification"
                                           : "Undo: bring back " + Notifs.undoCount + " cleared notifications"
    Accessible.description: "Control+Z"
}
