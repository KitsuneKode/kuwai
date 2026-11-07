// Software Update, grown out of the island (the update alert's "Review", the
// System panel, Super+Ctrl+Shift+U). Three views, drilled into in place:
//
//   list     Arch packages (one group: updated together, as Arch requires)
//            and AUR packages (each one reviewed before it can be chosen);
//            notices first: Arch news that asks for a manual step, low space,
//            low battery, a kernel update (restart after)
//   review   one AUR package: what changed in its build files since the
//            version you have (DiffView), lines worth a look, its commits;
//            Approve, or trust it from now on
//   run      the update as it happens: steps, progress, the live log; then
//            what's left for you (restart, .pacnew files, failed services)
//
// The work is bin/rice-update's (services/Updates). Passwords go to kuwai's
// prompt (shell-auth): one for Arch packages, one for the AUR installs.
//
// Keys: ↵ update (list) / approve (review) · Esc back · R check again.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.components.ui
import qs.services

FocusScope {
    id: up
    focus: true
    implicitWidth: 720
    implicitHeight: Math.min(560, (view === "review" ? 540 : view === "run" ? runCol.implicitHeight + 44 : listCol.y + listCol.implicitHeight + listFoot.height + 30))
    Behavior on implicitHeight { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    // A result only keeps the run view when this session actually started the job.
    // A restart must land on the package list (the review), not a stale failure.
    property string view: Updates.running || (Updates.ownedRun && Updates.result) ? "run" : "list"
    property string pkg: ""                       // the package under review
    property bool showAllRepo: false
    property bool showLog: false
    property int fileIx: 0

    function openReview(name) { pkg = name; fileIx = 0; Updates.review(name); go("review"); }
    // The island's Back row leads back to the list from a review (or a result).
    readonly property bool deep: view === "review" || (view === "run" && !Updates.running && !!Updates.result)
    function syncBack() {
        if (deep) { Island.innerBack = () => { if (up.view === "run") Updates.result = null; up.go("list"); }; Island.innerBackLabel = "Software Update"; }
        else if (Island.innerBackLabel === "Software Update") { Island.innerBack = null; Island.innerBackLabel = ""; }
    }
    onDeepChanged: syncBack()
    Component.onDestruction: if (Island.innerBackLabel === "Software Update") { Island.innerBack = null; Island.innerBackLabel = ""; }
    function go(v) { view = v; swap.restart(); }

    Component.onCompleted: {
        Updates.markViewed();
        Updates.checkIfStale();
        Updates.loadPacnew();
        // Read every AUR change now (the service also does on each check), so
        // the list can say which ones are only version bumps.
        for (const p of Updates.aur) if (Updates.aurState(p.name) === "review") Updates.review(p.name);
    }
    Connections {
        target: Updates
        function onRunningChanged() { if (Updates.running) up.go("run"); }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && view === "review") { go("list"); event.accepted = true; }
        else if (event.key === Qt.Key_Escape && view === "run" && !Updates.running && Updates.result) { Updates.result = null; go("list"); event.accepted = true; }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && view === "list") { Updates.run(); event.accepted = true; }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && view === "review") { Updates.approve(pkg); go("list"); event.accepted = true; }
        else if (event.key === Qt.Key_R && view === "list") { Updates.check(); event.accepted = true; }
    }

    // Drill-in: the new view drifts 14 px in from the side it came from.
    property real enter: 1
    NumberAnimation { id: swap; target: up; property: "enter"; from: 0; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    // ── Small building blocks ────────────────────────────────────────────
    // Chip, Button, Card, Notice: components/ui (one primitive per job).
    component Version: Row {
        property string from
        property string to
        readonly property var split: Updates.versionSplit(from, to)
        spacing: 0
        Label { text: parent.from; size: 11; color: Theme.textTertiary; font.features: ({ "tnum": 1 }) }
        Label { text: "  →  "; size: 11; color: Theme.textTertiary }
        Label { text: parent.split[0]; size: 11; color: Theme.textSecondary; font.features: ({ "tnum": 1 }) }
        Label { text: parent.split[1]; size: 11; weight: Theme.wSemibold; color: Theme.accent; font.features: ({ "tnum": 1 }) }
    }


    // Config files an update left beside yours (Updates.pacnew): each with
    // what the new default would change, a recommendation, and Keep mine /
    // Use new. One password applies them all.
    component ConfigReview: Card {
        visible: Updates.pacnew.length > 0 && !Updates.running
        Row {
            width: parent.width
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0219}"; font.family: Theme.fontGlyph; font.pixelSize: 16; color: Theme.textSecondary }
            Column {
                width: parent.width - 30
                spacing: 2
                Label { text: Updates.pacnew.length + " config files from updates"; size: 14; weight: Theme.wSemibold }
                Label { width: parent.width; wrapMode: Text.Wrap; text: "An update ships a new default beside a file you have (X.pacnew). Yours stays in use until you choose."; size: 11; color: Theme.textTertiary }
            }
        }
        Repeater {
            model: Updates.pacnew
            Item {
                id: row
                required property var modelData
                readonly property string choice: Updates.pacnewChoice[modelData.path] || ""
                width: parent.width
                height: info.implicitHeight + 12
                Column {
                    id: info
                    y: 6
                    width: parent.width - choices.width - 12
                    spacing: 2
                    Row {
                        spacing: 6
                        Label { text: row.modelData.name; size: 12; weight: Theme.wMedium; font.family: Theme.fontMono || Theme.fontText }
                        Chip {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            text: ({ keep: "keep yours", take: "use new", review: "look first" })[row.modelData.rec] || row.modelData.rec
                            tone: row.modelData.rec === "review" ? Theme.orange : Theme.textSecondary
                        }
                    }
                    Label { width: parent.width; wrapMode: Text.Wrap; text: row.modelData.why; size: 11; color: Theme.textSecondary }
                    Label {
                        visible: (row.modelData.gone || []).length > 0
                        width: parent.width; elide: Text.ElideRight
                        text: "New default drops: " + (row.modelData.gone || []).join(", ")
                        size: 10; color: Theme.textTertiary
                    }
                    Label {
                        visible: (row.modelData.added || []).length > 0
                        width: parent.width; elide: Text.ElideRight
                        text: "Adds: " + (row.modelData.added || []).join(", ")
                        size: 10; color: Theme.textTertiary
                    }
                    Label {
                        visible: !row.modelData.readable
                        width: parent.width; wrapMode: Text.Wrap
                        text: "See it: sudo diff /etc/" + row.modelData.name + "{,.pacnew}"
                        size: 10; color: Theme.textTertiary
                    }
                }
                Row {
                    id: choices
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Repeater {
                        model: [{ id: "keep", label: "Keep mine" }, { id: "take", label: "Use new" }]
                        Rectangle {
                            required property var modelData
                            readonly property bool on: row.choice === modelData.id
                            height: 26; radius: 13
                            width: chLabel.implicitWidth + 20
                            color: on ? Qt.rgba(1, 1, 1, 0.9) : chArea.containsMouse ? Theme.pillHover : Theme.pill
                            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                            Label { id: chLabel; anchors.centerIn: parent; text: parent.modelData.label; size: 11; weight: Theme.wMedium; color: parent.on ? "#111114" : Theme.textPrimary }
                            MouseArea { id: chArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Updates.choosePacnew(row.modelData.path, parent.modelData.id) }
                        }
                    }
                }
            }
        }
        Row {
            width: parent.width
            spacing: 10
            Button {
                primary: true
                text: Updates.pacnewBusy ? "Applying…" : "Apply " + Updates.pacnewChosen + (Updates.pacnewChosen === 1 ? " choice" : " choices")
                enabled: Updates.pacnewChosen > 0 && !Updates.pacnewBusy
                height: 30
                onClicked: Updates.applyPacnew()
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 180; wrapMode: Text.Wrap
                text: Updates.pacnewResult || "Use new keeps yours as X.rice-bak. sudoers is checked with visudo first."
                size: 11; color: Updates.pacnewResult ? Theme.textSecondary : Theme.textTertiary
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // List
    // ═════════════════════════════════════════════════════════════════════
    Flickable {
        id: listFlick
        visible: up.view === "list"
        opacity: up.view === "list" ? up.enter : 0
        x: (1 - up.enter) * -14
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: listFoot.top; bottomMargin: 8 }
        contentHeight: listCol.y + listCol.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: listCol
            x: 22; y: 20
            width: up.width - 44
            spacing: 12

            // Header
            Item {
                width: parent.width; height: 40
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label { text: Updates.total === 0 ? "Up to date" : "Software Update"; size: 18; weight: Theme.wSemibold }
                    Label {
                        text: Updates.checking ? "Checking…"
                            : Updates.total < 0 ? "Not checked yet"
                            : ([Updates.repo.length + " Arch", Updates.aur.length + " AUR", Updates.flatpak.length ? Updates.flatpak.length + " Flatpak" : ""].filter(x => x).join(" · ") + " · checked " + Updates.ago(Updates.checkedAt))
                        size: 12; color: Theme.textTertiary
                    }
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 34; height: 34; radius: 17
                    color: refArea.containsMouse ? Theme.pillHover : Theme.pill
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0450}"
                        font.family: Theme.fontGlyph; font.pixelSize: 15
                        color: Theme.textSecondary
                        RotationAnimation on rotation { running: Updates.checking && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                    }
                    MouseArea { id: refArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Updates.check() }
                    Tip { text: "Check again (R)"; shown: refArea.containsMouse; below: true }
                }
            }

            // Notices
            Notice {
                id: cancelNote
                // Re-evaluated every half minute so it goes away by itself.
                property real now: Date.now()
                Timer { running: cancelNote.visible; interval: 30000; repeat: true; onTriggered: cancelNote.now = Date.now() }
                visible: Updates.cancelledAt > 0 && now - Updates.cancelledAt < 5 * 60 * 1000
                glyph: "\u{f033e}"; tone: Theme.textSecondary
                title: "Cancelled at the password prompt"
                detail: "Nothing was changed. Update again when you're ready."
            }
            Repeater {
                model: Updates.manualNews
                Notice {
                    required property var modelData
                    glyph: "\u{f0026}"; title: modelData.title
                    detail: "Arch news asks for a manual step with this update. Read it before updating."
                    action: "Read"
                    onActed: Quickshell.execDetached(["xdg-open", modelData.link])
                }
            }
            Notice {
                visible: Updates.lowSpace
                glyph: "\u{f02ca}"; tone: Theme.red
                title: "Not enough space"
                detail: "Less than 3 GB free on your system drive. Free some space, then check again."
            }
            Notice {
                visible: Updates.lowPower
                glyph: "\u{f0083}"
                title: "Plug in first"
                detail: "The battery is below 30%. An update that's cut off by a dead battery can leave the system unbootable."
            }
            Notice {
                visible: !!(Updates.data && Updates.data.kernel) && Updates.includeRepo
                glyph: "\u{f0709}"; tone: Theme.accent
                title: "Includes a new kernel"
                detail: "Restart when it's done, so the new kernel and drivers load together."
            }
            Notice {
                visible: Updates.checkError !== "" || !!(Updates.data && Updates.data.repoError)
                glyph: "\u{f0026}"; tone: Theme.red
                title: "The check didn't finish"
                detail: Updates.checkError || (Updates.data ? String(Updates.data.repoError) : "")
                action: "Retry"
                onActed: Updates.check()
            }

            // Skeleton while the first check runs.
            Repeater {
                model: Updates.total < 0 ? 3 : 0
                Skeleton { width: listCol.width; height: 48; radius: 14 }
            }

            ConfigReview {}

            // Arch packages
            Card {
                visible: Updates.repo.length > 0
                Item {
                    width: parent.width; height: 34
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f08c7}"; font.family: Theme.fontGlyph; font.pixelSize: 20; color: Theme.accent }
                    Column {
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Label { text: "Arch Linux · " + Updates.repo.length + (Updates.repo.length === 1 ? " package" : " packages"); size: 14; weight: Theme.wSemibold }
                        Label { text: "Updated together, the way Arch supports"; size: 11; color: Theme.textTertiary }
                    }
                    Toggle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        on: Updates.includeRepo
                        onToggled: Updates.includeRepo = !Updates.includeRepo
                    }
                }
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 18
                    rowSpacing: 6
                    opacity: Updates.includeRepo ? 1 : 0.45
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Repeater {
                        model: up.showAllRepo ? Updates.repo : Updates.repo.slice(0, 8)
                        Item {
                            required property var modelData
                            width: (listCol.width - 28 - 18) / 2; height: 34
                            Label { width: parent.width; elide: Text.ElideRight; text: modelData.name; size: 13; weight: Theme.wMedium }
                            Version { y: 17; from: modelData.old; to: modelData.new }
                            Label { anchors.right: parent.right; text: modelData.repo; size: 10; color: Qt.rgba(1, 1, 1, 0.3); visible: modelData.repo !== "" && modelData.repo !== "extra" }
                        }
                    }
                }
                Label {
                    visible: Updates.repo.length > 8
                    text: up.showAllRepo ? "Show fewer" : "Show all " + Updates.repo.length + " ›"
                    size: 12; weight: Theme.wMedium; color: Theme.accent
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: up.showAllRepo = !up.showAllRepo }
                }
            }

            // AUR packages
            Card {
                visible: Updates.aur.length > 0
                Item {
                    width: parent.width; height: 34
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0393}"; font.family: Theme.fontGlyph; font.pixelSize: 19; color: Theme.accent }
                    Column {
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Label { text: "AUR · " + Updates.aur.length + (Updates.aur.length === 1 ? " package" : " packages"); size: 14; weight: Theme.wSemibold }
                        Label { text: "Built as you, from exactly the change you approve"; size: 11; color: Theme.textTertiary }
                    }
                    // Approve the plain version bumps in one go (each one was read).
                    Button {
                        readonly property var routine: Updates.aur.filter(p => Updates.aurState(p.name) === "review" && Updates.reviewOf(p.name) && Updates.reviewOf(p.name).routine && !Updates.reviewOf(p.name).flags.length)
                        visible: routine.length > 0
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        height: 28
                        glyph: "\u{f012c}"
                        text: "Approve " + routine.length + " version bump" + (routine.length > 1 ? "s" : "")
                        onClicked: { for (const p of routine) Updates.approve(p.name); }
                    }
                }
                Repeater {
                    model: Updates.aur
                    Item {
                        id: aurRow
                        required property var modelData
                        required property int index
                        readonly property string st: Updates.aurState(modelData.name)
                        readonly property var rv: Updates.reviewOf(modelData.name)
                        width: parent.width; height: 44
                        Rectangle { visible: aurRow.index > 0; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }
                        Rectangle {
                            anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2
                            radius: 10
                            color: rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: up.openReview(aurRow.modelData.name) }
                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: Updates.selectable(aurRow.modelData.name)
                            on: Updates.selected(aurRow.modelData.name)
                            opacity: enabled ? 1 : 0.35
                            onToggled: Updates.setExcluded(aurRow.modelData.name, Updates.selected(aurRow.modelData.name))
                        }
                        Column {
                            x: 56; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56 - stateChip.width - 40
                            spacing: 1
                            Label { width: parent.width; elide: Text.ElideRight; text: aurRow.modelData.name; size: 13; weight: Theme.wMedium }
                            Version { from: aurRow.modelData.old; to: aurRow.modelData.new }
                        }
                        Chip {
                            id: stateChip
                            anchors { right: chev.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            readonly property var look: {
                                const s = aurRow.st, r = aurRow.rv;
                                if (s === "trusted") return ["Trusted", Theme.accent, "\u{f0565}"];
                                if (s === "approved") return [Updates.autoApproved.indexOf(aurRow.modelData.name) >= 0 ? "Version bump · auto" : "Approved", Theme.green, "\u{f012c}"];
                                if (s === "loading" || !r) return ["Reading…", Theme.textTertiary, ""];
                                if (r.error) return ["Couldn't read", Theme.red, ""];
                                if (r.firstTime) return ["New to you · review", Theme.orange, "\u{f0026}"];
                                if (r.flags && r.flags.length) return [r.flags.length + " to look at", Theme.orange, "\u{f0026}"];
                                if (r.routine) return ["Version bump · review", Theme.green, ""];
                                return ["Changed · review", Theme.textSecondary, ""];
                            }
                            text: look[0]; tone: look[1]; glyph: look[2]
                        }
                        Text { id: chev; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: "\u{f0142}"; font.family: Theme.fontGlyph; font.pixelSize: 15; color: Theme.textTertiary }
                    }
                }
            }

            // Flatpak apps: sandboxed and signed, each updates on its own.
            Card {
                visible: Updates.flatpak.length > 0
                Item {
                    width: parent.width; height: 34
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f08c4}"; font.family: Theme.fontGlyph; font.pixelSize: 19; color: Theme.accent }
                    Column {
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Label { text: "Flatpak · " + Updates.flatpak.length + (Updates.flatpak.length === 1 ? " update" : " updates"); size: 14; weight: Theme.wSemibold }
                        Label { text: "Sandboxed and signed: pick any, no review needed"; size: 11; color: Theme.textTertiary }
                    }
                }
                Repeater {
                    model: Updates.flatpak
                    Item {
                        id: fpRow
                        required property var modelData
                        required property int index
                        width: parent.width; height: 42
                        Rectangle { visible: fpRow.index > 0; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }
                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            on: !Updates.flatpakOff[fpRow.modelData.id]
                            onToggled: Updates.setFlatpakOff(fpRow.modelData.id, !Updates.flatpakOff[fpRow.modelData.id])
                        }
                        Column {
                            x: 56; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56
                            spacing: 1
                            Label {
                                width: parent.width; elide: Text.ElideRight; size: 13; weight: Theme.wMedium
                                text: fpRow.modelData.name + "  ·  " + (fpRow.modelData.app || fpRow.modelData.id)
                                    + (fpRow.modelData.runtime ? "  ·  runtime" : "") + (fpRow.modelData.install === "system" ? "  ·  system-wide" : "")
                            }
                            Version { visible: fpRow.modelData.old !== ""; from: fpRow.modelData.old; to: fpRow.modelData.new }
                        }
                    }
                }
            }

            Item { width: 1; height: 4 }
        }
    }
    ScrollHint { visible: up.view === "list"; flickable: listFlick; anchors { right: parent.right; top: listFlick.top; bottom: listFlick.bottom; rightMargin: 4 } }

    // Footer: what will happen, and the button.
    Item {
        id: listFoot
        visible: up.view === "list" && Updates.total > 0
        opacity: up.enter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 22; rightMargin: 22; bottomMargin: 18 }
        height: visible ? 34 : 0
        Label {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; right: footBtns.left; rightMargin: 12 }
            elide: Text.ElideRight
            text: Updates.waitingReview > 0
                ? Updates.waitingReview + " AUR " + (Updates.waitingReview === 1 ? "package waits" : "packages wait") + " for your review"
                : "Sleep and shutdown wait until it's done"
            size: 11; color: Theme.textTertiary
        }
        Row {
            id: footBtns
            anchors.right: parent.right
            spacing: 8
            Button { glyph: "\u{f018d}"; text: "Terminal"; onClicked: { Island.close(); Updates.terminal(); } }
            Button {
                primary: true
                enabled: Updates.chosenCount > 0 && !Updates.lowSpace && !Updates.running
                text: Updates.chosenCount > 0 ? "Update " + Updates.chosenCount : "Nothing chosen"
                onClicked: Updates.run()
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // Review
    // ═════════════════════════════════════════════════════════════════════
    Item {
        id: reviewView
        visible: up.view === "review"
        opacity: up.view === "review" ? up.enter : 0
        x: (1 - up.enter) * 14
        width: parent.width; height: parent.height
        readonly property var r: Updates.reviewOf(up.pkg)
        readonly property var p: Updates.aur.find(a => a.name === up.pkg) || null
        readonly property var file: r && r.files && r.files.length ? r.files[Math.min(up.fileIx, r.files.length - 1)] : null

        // Back + title
        Item {
            id: rvHead
            x: 22; y: 12
            width: parent.width - 44; height: 44
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label { text: up.pkg; size: Theme.tTitle3; weight: Theme.wSemibold }
                Version { visible: !!reviewView.p; from: reviewView.p ? reviewView.p.old : ""; to: reviewView.p ? reviewView.p.new : "" }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!reviewView.r && !reviewView.r.error
                    readonly property var r: reviewView.r
                    text: !r ? "" : r.firstTime ? "First time: every file is new" : r.routine && !r.flags.length ? "Only versions and checksums changed" : r.flags.length ? r.flags.length + " lines worth a look" : "Changes beyond a version bump"
                    tone: !r ? Theme.textTertiary : r.routine && !r.flags.length ? Theme.green : (r.firstTime || r.flags.length) ? Theme.orange : Theme.textSecondary
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30; glyph: "\u{f03cc}"; text: "AUR"
                    enabled: !!reviewView.r && !!reviewView.r.url
                    onClicked: Quickshell.execDetached(["xdg-open", reviewView.r.url])
                }
            }
        }

        // Commits + flags
        Column {
            id: rvInfo
            x: 22; y: rvHead.y + rvHead.height + 10
            width: parent.width - 44
            spacing: 6
            Repeater {
                model: reviewView.r && reviewView.r.commits ? reviewView.r.commits.slice(0, 2) : []
                Row {
                    required property var modelData
                    spacing: 8
                    Label { text: modelData.sha; size: 11; font.family: Theme.fontMono; color: Theme.accent }
                    Label { text: modelData.subject; size: 12; color: Theme.textSecondary; width: Math.min(implicitWidth, rvInfo.width - 260); elide: Text.ElideRight }
                    Label { text: modelData.author + " · " + modelData.when; size: 11; color: Theme.textTertiary }
                }
            }
            // Its standing in the AUR: how many use it, who keeps it, how old.
            Row {
                readonly property var c: reviewView.r ? reviewView.r.community : null
                visible: !!c
                spacing: 6
                Chip {
                    readonly property var c: parent.c
                    text: c ? (c.established ? "Established" : "Not established") : ""
                    tone: c && c.established ? Theme.green : Theme.orange
                    glyph: c && c.established ? "\u{f012c}" : "\u{f0026}"
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property var c: parent.c
                    readonly property real years: c ? (Date.now() / 1000 - c.firstSubmitted) / (365 * 86400) : 0
                    text: !c ? "" : [c.votes + (c.votes === 1 ? " vote" : " votes"), "popularity " + c.popularity,
                                     c.maintainer ? "kept by " + c.maintainer : "orphaned",
                                     years >= 1 ? Math.floor(years) + (Math.floor(years) === 1 ? " year" : " years") + " on the AUR" : Math.max(1, Math.round(years * 12)) + " months on the AUR",
                                     c.outOfDate ? "flagged out of date" : "",
                                     c.binary ? "prebuilt program (not reviewable)" : ""].filter(x => x).join(" · ")
                    size: 11; color: Theme.textTertiary
                }
            }
            Flow {
                width: parent.width
                spacing: 6
                visible: !!(reviewView.r && reviewView.r.flags && reviewView.r.flags.length)
                Repeater {
                    model: reviewView.r && reviewView.r.flags ? reviewView.r.flags : []
                    Chip {
                        required property var modelData
                        tone: Theme.orange; glyph: "\u{f0026}"
                        text: modelData.why + " · " + modelData.path + ":" + modelData.line
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const i = reviewView.r.files.findIndex(f => f.path === modelData.path);
                                if (i >= 0) up.fileIx = i;
                                Qt.callLater(() => diff.scrollToLine(modelData.line));
                            }
                        }
                    }
                }
            }
            Segmented {
                visible: !!(reviewView.r && reviewView.r.files && reviewView.r.files.length > 1)
                options: reviewView.r && reviewView.r.files ? reviewView.r.files.map((f, i) => ({ id: String(i), label: f.path + "  +" + f.add + " −" + f.del })) : []
                current: String(up.fileIx)
                onPicked: id => up.fileIx = parseInt(id)
            }
        }

        DiffView {
            id: diff
            x: 22
            anchors { top: rvInfo.bottom; topMargin: 10; bottom: rvFoot.top; bottomMargin: 12 }
            width: parent.width - 44
            file: reviewView.file
            flags: reviewView.r ? reviewView.r.flags : []
            visible: !!reviewView.r && !reviewView.r.error
        }
        Skeleton {
            visible: !reviewView.r
            x: 22; width: parent.width - 44
            anchors { top: rvInfo.bottom; topMargin: 10; bottom: rvFoot.top; bottomMargin: 12 }
            radius: 12
        }
        Label {
            visible: !!(reviewView.r && reviewView.r.error)
            anchors.centerIn: diff
            text: reviewView.r ? (reviewView.r.error || "") : ""
            size: 12; color: Theme.red
        }

        Item {
            id: rvFoot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 22; rightMargin: 22; bottomMargin: 18 }
            height: 34
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    on: Updates.trusted.indexOf(up.pkg) >= 0
                    onToggled: Updates.setTrusted(up.pkg, !on)
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label { text: "Trust " + up.pkg; size: 12; weight: Theme.wMedium }
                    Label { text: "Skip reviewing its future updates"; size: 11; color: Theme.textTertiary }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button {
                    visible: Updates.aurState(up.pkg) === "approved"
                    text: "Withdraw"
                    onClicked: Updates.unapprove(up.pkg)
                }
                Button {
                    primary: true
                    readonly property bool done: Updates.aurState(up.pkg) === "approved" || Updates.aurState(up.pkg) === "trusted"
                    enabled: !!reviewView.r && !reviewView.r.error && !done
                    glyph: done ? "\u{f012c}" : ""
                    text: done ? "Approved" : "Approve this change"
                    onClicked: { Updates.approve(up.pkg); up.go("list"); }
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // Run (and the result)
    // ═════════════════════════════════════════════════════════════════════
    Column {
        id: runCol
        visible: up.view === "run"
        opacity: up.view === "run" ? up.enter : 0
        x: 22 + (1 - up.enter) * 14; y: 20
        width: up.width - 44
        spacing: 14
        readonly property var res: Updates.result
        readonly property bool ok: !!res && res.ok && !Updates.runError

        Item {
            width: parent.width; height: 44
            Rectangle {
                id: runBadge
                width: 44; height: 44; radius: 22
                color: Updates.running ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                     : runCol.ok ? Qt.rgba(0.19, 0.82, 0.35, 0.18) : Qt.rgba(1, 0.62, 0.04, 0.18)
                Text {
                    anchors.centerIn: parent
                    text: Updates.running ? "\u{f06b0}" : runCol.ok ? "\u{f012c}" : "\u{f0026}"
                    font.family: Theme.fontGlyph; font.pixelSize: 20
                    color: Updates.running ? Theme.accent : runCol.ok ? Theme.green : Theme.orange
                    RotationAnimation on rotation { running: Updates.running && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                }
            }
            Column {
                x: 56; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 56
                spacing: 2
                Label {
                    text: Updates.running ? "Updating" : runCol.ok ? "All done" : (runCol.res && runCol.res.cancelled) ? "Cancelled"
                        : (runCol.res && runCol.res.unknown) ? "Update stopped" : "Finished, with things to look at"
                    size: 18; weight: Theme.wSemibold
                }
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: Updates.running ? Updates.phaseLabel
                        : Updates.runError || (runCol.res ? [runCol.res.repo ? "Arch packages updated" : "", runCol.res.installed && runCol.res.installed.length ? runCol.res.installed.length + " AUR installed" : ""].filter(x => x).join(" · ") : "")
                    size: 12; color: Updates.runError ? Theme.orange : Theme.textTertiary
                }
            }
        }

        // Progress
        Item {
            visible: Updates.running
            width: parent.width; height: 26
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6; radius: 3
                color: Theme.pill
                Rectangle {
                    width: parent.width * Updates.progress; height: parent.height; radius: 3
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                }
            }
        }

        // Steps
        Column {
            width: parent.width
            spacing: 6
            Repeater {
                model: [
                    { id: "check", label: "Space and power" },
                    ...(Updates.plan.repo ? [{ id: "repo", label: "Arch packages" }] : []),
                    ...(Updates.plan.aur.length ? [{ id: "build", label: "Build AUR packages, as you" }, { id: "install", label: "Install AUR packages" }] : []),
                    ...(Updates.plan.flatpak && Updates.plan.flatpak.length ? [{ id: "flatpak", label: "Flatpak" }] : []),
                    { id: "after", label: "Finish up" }
                ]
                Row {
                    required property var modelData
                    readonly property bool seen: Updates.phasesSeen.indexOf(modelData.id) >= 0
                    readonly property bool now: Updates.running && Updates.phase === modelData.id
                    // The run is over and this step never ran (its packages were skipped):
                    // say so, instead of an empty circle that looks like it stalled.
                    // (Not after a run that ended unexplained: "skipped" would be a guess.)
                    readonly property bool skipped: !Updates.running && !!runCol.res && !runCol.res.unknown && !seen
                    spacing: 10
                    Text {
                        width: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.now ? "\u{f0997}" : parent.seen ? "\u{f012c}" : parent.skipped ? "\u{f0374}" : "\u{f0766}"
                        font.family: Theme.fontGlyph; font.pixelSize: 13
                        color: parent.now ? Theme.accent : parent.seen ? Theme.green : Theme.textTertiary
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: modelData.label + (parent.skipped ? " · skipped" : ""); size: 13; weight: parent.now ? Theme.wSemibold : Theme.wRegular; color: parent.seen || parent.now ? Theme.textPrimary : Theme.textTertiary }
                }
            }
        }

        // The current line, then the log on request.
        Label {
            visible: Updates.running && !up.showLog
            width: parent.width; elide: Text.ElideRight
            text: Updates.currentLine
            size: 11; font.family: Theme.fontMono; color: Theme.textTertiary
        }

        // What needs you now.
        Notice {
            visible: !Updates.running && !!runCol.res && !!runCol.res.restart
            glyph: "\u{f0709}"; tone: Theme.accent
            title: "Restart to finish"
            detail: "A new kernel is installed; the running one's modules are gone until you restart."
            action: "Restart"
            onActed: Updates.restart()
        }
        Repeater {
            model: !Updates.running && runCol.res && runCol.res.skipped ? runCol.res.skipped : []
            Notice {
                required property var modelData
                glyph: "\u{f0026}"
                title: modelData.pkg + " wasn't updated"
                detail: modelData.why
            }
        }
        // Asked more than once: offer the one-password helper (asks once more, to set it up).
        Notice {
            visible: !Updates.running && !!runCol.res && runCol.res.oneprompt === false && (runCol.res.prompts || 0) > 1 && Updates.helperState !== "done"
            glyph: "\u{f0306}"; tone: Theme.accent
            title: Updates.helperState === "failed" ? "Not set up (cancelled?)" : "Asked for your password " + (runCol.res ? runCol.res.prompts : 0) + " times"
            detail: "Set up once (your password one more time) and every update after asks just once."
            action: Updates.helperState === "working" ? "" : "Set up"
            onActed: Updates.setupOnePrompt()
        }
        ConfigReview {}
        Notice {
            visible: !Updates.running && !!runCol.res && !!runCol.res.failedUnits && runCol.res.failedUnits.length > 0
            glyph: "\u{f0026}"; tone: Theme.red
            title: "Services that failed"
            detail: runCol.res && runCol.res.failedUnits ? runCol.res.failedUnits.join(" · ") : ""
        }

        Rectangle {
            visible: up.showLog
            width: parent.width; height: 190; radius: 12
            color: Qt.rgba(0, 0, 0, 0.35)
            ListView {
                id: logList
                anchors { fill: parent; margins: 10 }
                clip: true
                model: Updates.log
                onCountChanged: if (atYEnd || count < 3) positionViewAtEnd()
                delegate: Text {
                    required property var modelData
                    width: logList.width
                    text: modelData
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.fontMono; font.pixelSize: 11
                    color: /error|failed|warning/i.test(modelData) ? Theme.orange : Theme.textSecondary
                }
            }
        }

        Item {
            width: parent.width; height: 34
            Button {
                anchors.left: parent.left
                glyph: "\u{f0219}"
                text: up.showLog ? "Hide log" : "Show log"
                onClicked: up.showLog = !up.showLog
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { visible: !Updates.running && !!runCol.res && !!runCol.res.log; text: "Open log file"; onClicked: Updates.openLog() }
                Button {
                    visible: !Updates.running
                    primary: true
                    text: "Done"
                    onClicked: { Updates.result = null; up.go("list"); }
                }
            }
        }
    }
}
