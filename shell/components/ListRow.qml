// One row for every list (T3, Agents, the launcher's results, the center's
// notifications): a leading mark, a title, a quiet second line, a state word
// at the right edge (or a trailing item of the list's own), and anything
// below it (a question, buttons, a reply preview) aligned to the text. The
// four lists drew their own rows with insets of 10/12/14 px, text columns at
// 36/52/58 px and states placed differently; on these metrics (Theme.row*)
// they line up.
//
// Where there is no room for the state beside the whole title (a large Text
// size, a long title) it goes under it, and the title may take two lines. Lengths that hold text are
// Theme.sp(); nothing here knows the list's data. The list keeps its own
// delegate around it (swipes, the hover ×, its ContextMenu, its highlight).
//
//   ListRow {
//       width: list.width
//       lead: Image { anchors.centerIn: parent; … }     // centred in a Theme.rowMark box
//       title: modelData.title; sub: "Codex · rice"
//       stateText: "Working 23m"; stateColor: Theme.textTertiary
//       Label { width: parent.width; text: modelData.question }   // below the line
//   }
import QtQuick
import qs.config

Item {
    id: lr
    property alias lead: leadBox.data
    default property alias below: belowCol.data
    property string title
    property int titleFormat: Text.PlainText
    property color titleColor: Theme.textPrimary
    property int titleSize: Theme.tBody
    property int titleWeight: Theme.wSemibold
    property string sub
    property int subFormat: Text.PlainText
    property color subColor: Theme.textTertiary
    property int subSize: Theme.tFootnote
    property bool titleRounded: false
    property string stateText                         // (not `state`: every Item has one)
    property color stateColor: Theme.textTertiary
    property int stateWeight: Theme.wMedium
    property real stateOpacity: 1                     // the hover × takes its place
    property alias trailOpacity: trailBox.opacity
    property alias trail: trailBox.data               // instead of stateText: the list's own (a key hint)
    readonly property bool hasTrail: trailBox.children.length > 0
    // Stacked when there is no room for the state beside the whole title: at a
    // large Text size always, and on any row whose title would otherwise be cut.
    property bool forceStacked: Theme.textScale >= 1.5
    readonly property real sideRoom: width - textX - Theme.rowInset - (hasTrail ? trailBox.width : stateMeasure.width) - Theme.s3
    readonly property bool stacked: forceStacked || (stateText !== "" && !hasTrail && titleMeasure.width > sideRoom)
    TextMetrics { id: titleMeasure; text: lr.title; font: titleLabel.font }
    TextMetrics { id: stateMeasure; text: lr.stateText; font: stateLabel.font }
    property real minHeight: Theme.sp(Theme.rowMin)
    readonly property real textX: Theme.rowInset + Theme.rowMark + Theme.rowGap
    readonly property real line: Math.max(minHeight, words.implicitHeight + Theme.s3)
    readonly property real belowHeight: belowCol.children.length && belowCol.implicitHeight > 0 ? belowCol.implicitHeight + Theme.s2 : 0

    implicitHeight: line + belowHeight

    Item {
        id: leadBox
        x: Theme.rowInset
        y: (lr.line - height) / 2
        width: Theme.rowMark; height: Theme.rowMark
    }
    Label {
        id: stateLabel
        visible: !lr.stacked && !lr.hasTrail && lr.stateText !== ""
        anchors { right: parent.right; rightMargin: Theme.rowInset }
        y: words.y + (titleLabel.height - height) / 2
        opacity: lr.stateOpacity
        text: lr.stateText
        size: Theme.tFootnote; weight: lr.stateWeight
        color: lr.stateColor
        font.features: ({ "tnum": 1 })
    }
    Item {
        id: trailBox
        anchors { right: parent.right; rightMargin: Theme.rowInset }
        y: (lr.line - height) / 2
        width: childrenRect.width; height: childrenRect.height
    }
    Column {
        id: words
        x: lr.textX
        y: (lr.line - height) / 2
        width: lr.width - x - Theme.rowInset
             - (lr.hasTrail ? (trailBox.opacity > 0 && trailBox.width > 0 ? trailBox.width + Theme.s3 : 0)
                : stateLabel.visible ? stateLabel.implicitWidth + Theme.s3 : 0)
        spacing: 2
        Label {
            id: titleLabel
            width: parent.width; elide: Text.ElideRight
            wrapMode: lr.stacked ? Text.Wrap : Text.NoWrap
            maximumLineCount: lr.stacked ? 2 : 1
            textFormat: lr.titleFormat
            text: lr.title
            size: lr.titleSize; weight: lr.titleWeight; rounded: lr.titleRounded
            color: lr.titleColor
        }
        // Stacked: the state under the title, in its colour.
        Label {
            visible: lr.stacked && lr.stateText !== ""
            width: parent.width; elide: Text.ElideRight
            text: lr.stateText
            size: Theme.tFootnote; weight: lr.stateWeight
            color: lr.stateColor
            font.features: ({ "tnum": 1 })
        }
        Label {
            visible: lr.sub !== ""
            width: parent.width; elide: Text.ElideRight
            textFormat: lr.subFormat
            text: lr.sub
            size: lr.subSize
            color: lr.subColor
        }
    }
    Column {
        id: belowCol
        x: lr.textX
        y: lr.line
        width: lr.width - x - Theme.rowInset
        spacing: Theme.s1
    }
}
