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
// The work is bin/kuwai-update's (services/Updates). Passwords go to kuwai's
// prompt (shell-auth): one for Arch packages, one for the AUR installs.
//
// Keys: ↵ update (list) / approve (review) · Esc back · R check again.
// A package row: Tab reaches it, ↵ reviews (AUR), Space includes or leaves
// it out, Menu or Shift+F10 (or a right-click) opens what else it offers.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.components.ui
import qs.services
import "../../services/links.mjs" as Links

FocusScope {
    id: up
    focus: true
    implicitWidth: Theme.panelL
    // The list view is exactly its content plus the footer: a guessed constant
    // here left the list 4 px short, so it "scrolled" (and faded) with nothing to scroll.
    implicitHeight: Math.min(560, (view === "review" || view === "pkgs" ? 540 : view === "run" ? runCol.implicitHeight + 44
        : listFlick.contentHeight + listFlick.anchors.bottomMargin + listFoot.height + listFoot.anchors.bottomMargin))
    Behavior on implicitHeight { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    // A result only keeps the run view when this session actually started the job.
    // A restart must land on the package list (the review), not a stale failure.
    property string view: Updates.running || (Updates.ownedRun && Updates.result) ? "run" : "list"
    property string pkg: ""                       // the package under review
    property bool showAllRepo: false
    readonly property string checkTrouble: Updates.checkError || (Updates.data && typeof Updates.data.repoError === "string" ? Updates.data.repoError : "")
    readonly property bool checkFailed: Updates.checkError !== "" || !!(Updates.data && Updates.data.repoError)
    readonly property string phase: checkFailed && Updates.total <= 0 ? "error" : Updates.total < 0 ? "loading" : Updates.total === 0 ? "empty" : "content"
    property bool showLog: false
    property int fileIx: 0
    property string menuOf: ""                    // a package whose menu is open (the rehearsal stages it)

    function openReview(name) { pkg = name; fileIx = 0; Updates.review(name); go("review"); }
    function openAurRow(row) {
        if (Updates.aurReadOnly) { if (row.page !== "") Apps.open(row.page); return; }
        openReview(row.modelData.name);
    }
    property bool installing: false
    function openInstall(name) { installing = true; openReview(name); }
    function takeAsk() { if (Updates.installAsk) { const n = Updates.installAsk; Updates.installAsk = ""; openInstall(n); } }
    function approveHere() {
        if (installing) Updates.approveAndInstall(pkg);
        else { Updates.approve(pkg); go("list"); }
    }
    // The island's Back row leads back to the list from a review (or a result).
    readonly property bool deep: view === "review" || view === "pkgs" || (view === "run" && !Updates.running && !!Updates.result)
    property alias packages: pkgView.list
    function syncBack() {
        if (deep) { Island.innerBack = () => { if (up.view === "run") Updates.result = null; up.go("list"); }; Island.innerBackLabel = "Software Update"; }
        else if (Island.innerBackLabel === "Software Update") { Island.innerBack = null; Island.innerBackLabel = ""; }
    }
    onDeepChanged: syncBack()
    Component.onDestruction: if (Island.innerBackLabel === "Software Update") { Island.innerBack = null; Island.innerBackLabel = ""; }
    function go(v) { if (v !== "review" && v !== "run") installing = false; view = v; swap.restart(); }

    Component.onCompleted: {
        Updates.markViewed();
        Updates.checkIfStale();
        Updates.loadPacnew();
        // Read every AUR change now (the service also does on each check), so
        // the list can say which ones are only version bumps.
        for (const p of Updates.aur) if (Updates.aurState(p.name) === "review") Updates.review(p.name);
        takeAsk();
    }
    Connections {
        target: Updates
        function onRunningChanged() { if (Updates.running) up.go("run"); }
        function onInstallAskChanged() { up.takeAsk(); }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && (view === "review" || view === "pkgs")) { go("list"); event.accepted = true; }
        else if (event.key === Qt.Key_Escape && view === "run" && !Updates.running && Updates.result) { Updates.result = null; go("list"); event.accepted = true; }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && view === "list") { Updates.run(); event.accepted = true; }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && view === "review") { approveHere(); event.accepted = true; }
        else if (event.key === Qt.Key_R && view === "list") { Updates.check(); event.accepted = true; }
    }

    // Drill-in: the new view drifts 14 px in from the side it came from.
    property real enter: 1
    NumberAnimation { id: swap; target: up; property: "enter"; from: 0; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    // ── Small building blocks ────────────────────────────────────────────
    // Chip, Button, Card, Notice: components/ui (one primitive per job).
    component Version: Row {
        property string from
        property string to
        readonly property var split: Updates.versionSplit(from, to)
        spacing: 0
        Label { text: parent.from; size: Theme.tFootnote; color: Theme.textTertiary; tabular: true }
        Label { text: "  →  "; size: Theme.tFootnote; color: Theme.textTertiary }
        Label { text: parent.split[0]; size: Theme.tFootnote; color: Theme.textSecondary; tabular: true }
        Label { text: parent.split[1]; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.accent; tabular: true }
    }


    // Config files an update left beside yours (Updates.pacnew): each with
    // what the new default would change, a recommendation, and Keep mine /
    // Use new. One password applies them all.
    component ConfigReview: Card {
        visible: Updates.pacnew.length > 0 && !Updates.running
        Row {
            width: parent.width
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0219}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphS; color: Theme.textSecondary }
            Column {
                width: parent.width - 30
                spacing: 2
                Label { text: Updates.pacnew.length + " config files from updates"; size: Theme.tCallout; weight: Theme.wSemibold }
                Label { width: parent.width; wrapMode: Text.Wrap; text: "An update ships a new default beside a file you have (X.pacnew). Yours stays in use until you choose."; size: Theme.tFootnote; color: Theme.textTertiary }
            }
        }
        Repeater {
            model: Updates.pacnew
            Item {
                id: row
                required property var modelData
                readonly property string choice: Updates.pacnewChoice[modelData.path] || ""
                width: parent.width
                height: Math.max(info.implicitHeight, choices.height) + 12
                Column {
                    id: info
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - choices.width - 12
                    spacing: 2
                    Row {
                        spacing: 6
                        Label { text: row.modelData.name; size: Theme.tSub; weight: Theme.wMedium; font.family: Theme.fontMono || Theme.fontText }
                        Chip {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            text: ({ keep: "keep yours", take: "use new", review: "look first" })[row.modelData.rec] || row.modelData.rec
                            tone: row.modelData.rec === "review" ? Theme.orange : Theme.textSecondary
                        }
                    }
                    Label { width: parent.width; wrapMode: Text.Wrap; text: row.modelData.why; size: Theme.tFootnote; color: Theme.textSecondary }
                    Label {
                        visible: (row.modelData.gone || []).length > 0
                        width: parent.width; elide: Text.ElideRight
                        text: "New default drops: " + (row.modelData.gone || []).join(", ")
                        size: Theme.tFootnote; color: Theme.textTertiary
                    }
                    Label {
                        visible: (row.modelData.added || []).length > 0
                        width: parent.width; elide: Text.ElideRight
                        text: "Adds: " + (row.modelData.added || []).join(", ")
                        size: Theme.tFootnote; color: Theme.textTertiary
                    }
                    Label {
                        visible: !row.modelData.readable
                        width: parent.width; wrapMode: Text.Wrap
                        text: "See it: sudo diff /etc/" + row.modelData.name + "{,.pacnew}"
                        size: Theme.tFootnote; color: Theme.textTertiary
                    }
                }
                // Keep mine / Use new: one choice of two, the Segmented primitive.
                Segmented {
                    id: choices
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    options: [{ id: "keep", label: "Keep mine" }, { id: "take", label: "Use new" }]
                    current: row.choice
                    onPicked: id => Updates.choosePacnew(row.modelData.path, id)
                    Accessible.name: "Config file " + row.modelData.name
                }
            }
        }
        Row {
            width: parent.width
            spacing: 10
            Button {
                id: applyChoices
                primary: true
                text: Updates.pacnewBusy ? "Applying…" : "Apply " + Updates.pacnewChosen + (Updates.pacnewChosen === 1 ? " choice" : " choices")
                enabled: Updates.pacnewChosen > 0 && !Updates.pacnewBusy
                onClicked: Updates.applyPacnew()
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - applyChoices.width - parent.spacing; wrapMode: Text.Wrap
                text: Updates.pacnewResult || "Use new saves yours in /var/lib/kuwai/pacnew-backups. sudoers is checked with visudo first."
                size: Theme.tFootnote; color: Updates.pacnewResult ? Theme.textSecondary : Theme.textTertiary
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
                width: parent.width; height: Math.max(Theme.sp(40), headWords.implicitHeight)
                Column {
                    id: headWords
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - refresh.width - Theme.s3
                    spacing: 2
                    Label { text: up.phase === "empty" ? "Up to date" : "Software Update"; size: Theme.tTitle3; weight: Theme.wSemibold }
                    Label {
                        visible: text !== ""
                        text: Updates.checking ? "Checking…"
                            : up.phase === "error" ? ""
                            : Updates.total < 0 ? "Not checked yet"
                            : up.checkFailed ? (up.checkTrouble && up.checkTrouble !== "Couldn't read the update check" ? up.checkTrouble : "The latest check didn't finish") + " · this is the one before"
                            : ([Updates.repoLive.length + " Arch", Updates.aurLive.length + " AUR", Updates.flatpak.length ? Updates.flatpak.length + " Flatpak" : "",
                                Updates.heldCount ? Updates.heldCount + " held" : ""].filter(x => x).join(" · ") + " · checked " + Updates.ago(Updates.checkedAt))
                        width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        size: Theme.tSub; color: !Updates.checking && Updates.total >= 0 && up.checkFailed ? Theme.orange : Theme.textTertiary
                    }
                }
                Button {
                    id: refresh
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    kind: "quiet"
                    glyph: "\u{f0450}"
                    label: Updates.checking ? "Checking for updates" : up.checkFailed ? "Retry the check (R)" : "Check again (R)"
                    busy: Updates.checking
                    onClicked: Updates.check()
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
                    action: Links.safeLink(modelData.link) ? "Read" : ""
                    onActed: if (Links.safeLink(modelData.link)) Apps.open(modelData.link)
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
                visible: up.phase === "error"
                glyph: "\u{f0026}"; tone: Theme.red
                title: "The check didn't finish"
                detail: up.checkTrouble && up.checkTrouble !== "Couldn't read the update check" ? up.checkTrouble : ""
                action: "Retry"
                onActed: Updates.check()
            }

            // Skeleton while the first check runs; not once it has failed (the
            // rows stayed under "The check didn't finish", promising a list).
            Repeater {
                model: up.phase === "loading" ? 3 : 0
                Skeleton { width: listCol.width; height: 48; radius: 14 }
            }

            ConfigReview {}

            // Arch packages
            Card {
                visible: Updates.repo.length > 0
                Item {
                    width: parent.width; height: Math.max(Theme.sp(34), archHead.implicitHeight)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f08c7}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphM; color: Theme.accent }
                    Column {
                        id: archHead
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - archToggle.width - Theme.s3
                        spacing: 1
                        Label { text: "Arch Linux · " + Updates.repo.length + (Updates.repo.length === 1 ? " package" : " packages"); size: Theme.tCallout; weight: Theme.wSemibold }
                        Label {
                            width: parent.width; wrapMode: Text.Wrap
                            text: Updates.repo.length > Updates.repoLive.length ? (Updates.repo.length - Updates.repoLive.length) + " held at the version you have; the rest together, the way Arch supports"
                                : "Updated together, the way Arch supports · clear a check to hold one"
                            size: Theme.tFootnote; color: Theme.textTertiary
                        }
                    }
                    Toggle {
                        id: archToggle
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        label: "Include Arch packages"
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
                    Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                    Repeater {
                        model: up.showAllRepo ? Updates.repo : Updates.repo.slice(0, 8)
                        Item {
                            id: repoRow
                            required property var modelData
                            // Its own height: at a fixed 34 the version line sat on the name at 120 % text.
                            width: (listCol.width - 28 - 18) / 2; height: pkg.implicitHeight + 3
                            ContextMenu {
                                target: repoRow
                                bounds: up
                                title: repoRow.modelData.name
                                ContextMenuLabel { text: repoRow.modelData.name }
                                ContextMenuItem { text: "Copy name"; glyph: "\u{f018f}"; onTriggered: Clipboard.copyText(repoRow.modelData.name) }
                                ContextMenuItem { text: "Copy name and versions"; onTriggered: Clipboard.copyText(repoRow.modelData.name + " " + repoRow.modelData.old + " → " + repoRow.modelData.new) }
                                ContextMenuSeparator {}
                                ContextMenuCheckboxItem { text: "Hold at " + repoRow.modelData.old; checked: Updates.isHeld(repoRow.modelData.name); onToggled: on => Updates.setHeld(repoRow.modelData.name, on) }
                                ContextMenuCheckboxItem { text: "Include Arch packages"; checked: Updates.includeRepo; onToggled: on => Updates.includeRepo = on }
                            }
                            readonly property bool held: Updates.isHeld(modelData.name)
                            Rectangle {
                                id: holdBox
                                y: Theme.s1 / 2
                                width: Theme.sp(16); height: width; radius: Theme.r1 / 2
                                color: repoRow.held ? "transparent" : Theme.accent
                                border.width: repoRow.held ? 1 : 0; border.color: Theme.textTertiary
                                Text {
                                    visible: !repoRow.held
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: "\u{f012c}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.tCaption
                                    color: Theme.onAccent
                                }
                                TapHandler { margin: Theme.s1; onTapped: Updates.setHeld(repoRow.modelData.name, !repoRow.held) }
                                HoverHandler { margin: Theme.s1; cursorShape: Qt.PointingHandCursor }
                                Accessible.role: Accessible.CheckBox
                                Accessible.checked: !repoRow.held
                                Accessible.name: (repoRow.held ? "Held: " : "Update ") + repoRow.modelData.name
                                Accessible.onPressAction: Updates.setHeld(repoRow.modelData.name, !repoRow.held)
                            }
                            Column {
                                id: pkg
                                x: holdBox.width + Theme.s2
                                width: parent.width - x
                                spacing: 1
                                Label { width: parent.width; elide: Text.ElideRight; text: modelData.name; size: Theme.tBody; weight: Theme.wMedium; color: repoRow.held ? Theme.textSecondary : Theme.textPrimary }
                                Version { visible: !repoRow.held; from: modelData.old; to: modelData.new }
                                Label { visible: repoRow.held; text: "Held at " + modelData.old; size: Theme.tFootnote; color: Theme.textSecondary }
                            }
                            Label { anchors.right: parent.right; text: modelData.repo; size: Theme.tCaption; color: Theme.textTertiary; visible: modelData.repo !== "" && modelData.repo !== "extra" }
                        }
                    }
                }
                Label {
                    visible: Updates.repoExtra.length > 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "pacman also installs " + Updates.repoExtra.slice(0, 6).map(p => p.name).join(", ")
                        + (Updates.repoExtra.length > 6 ? " and " + (Updates.repoExtra.length - 6) + " more" : "")
                        + " (new dependencies or replacements)"
                    size: Theme.tFootnote; color: Theme.textSecondary
                }
                Button {
                    visible: Updates.repo.length > 8
                    kind: "quiet"
                    size: Theme.tSub
                    text: up.showAllRepo ? "Show fewer" : "Show all " + Updates.repo.length
                    onClicked: up.showAllRepo = !up.showAllRepo
                }
            }

            // AUR packages
            Card {
                id: aurCard
                visible: Updates.aur.length > 0
                property Item hoverRow: null
                Item {
                    width: parent.width; height: Math.max(Theme.sp(34), aurHead.implicitHeight)
                    FluidHighlight { target: aurCard.hoverRow; radius: Theme.r1 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0393}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphM; color: Theme.accent }
                    Column {
                        id: aurHead
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 32 - (bumps.visible ? bumps.width + Theme.s3 : 0)
                        spacing: 1
                        Label { text: "AUR · " + Updates.aur.length + (Updates.aur.length === 1 ? " package" : " packages"); size: Theme.tCallout; weight: Theme.wSemibold }
                        Label { width: parent.width; elide: Text.ElideRight; text: Updates.aurReadOnly ? "Read-only here · update from a terminal with an AUR helper" : "Built as you, from exactly the change you approve"; size: Theme.tFootnote; color: Theme.textTertiary }
                    }
                    // Approve the plain version bumps in one go (each one was read).
                    Button {
                        id: bumps
                        readonly property var routine: Updates.aur.filter(p => Updates.aurState(p.name) === "review" && Updates.reviewOf(p.name) && Updates.reviewOf(p.name).routine && !Updates.reviewOf(p.name).flags.length)
                        visible: routine.length > 0
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
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
                        readonly property string page: Links.webLink(rv && rv.url ? rv.url : "https://aur.archlinux.org/packages/" + encodeURIComponent(modelData.name))
                        width: parent.width; height: Math.max(Theme.sp(44), aurWords.implicitHeight + Theme.s2)
                        Rectangle { visible: aurRow.index > 0; width: parent.width; height: 1; color: Theme.cardEdge }
                        Rectangle {
                            id: aurWash
                            anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2
                            radius: Theme.r1
                            color: aurMenu.open ? Theme.rowHover : "transparent"
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: up.openAurRow(aurRow)
                            onContainsMouseChanged: {
                                if (containsMouse) aurCard.hoverRow = aurWash;
                                else if (aurCard.hoverRow === aurWash) aurCard.hoverRow = null;
                            }
                        }
                        // Keyboard: Tab reaches the row; ↵ reviews it, Space includes or leaves it out, Menu / Shift+F10 its menu.
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            if (aurMenu.handleKey(e)) return;
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { up.openAurRow(aurRow); e.accepted = true; }
                            else if (e.key === Qt.Key_Space && Updates.selectable(aurRow.modelData.name)) { Updates.setExcluded(aurRow.modelData.name, Updates.selected(aurRow.modelData.name)); e.accepted = true; }
                        }
                        FocusRing { anchors.fill: aurWash; cornerRadius: Theme.r1 }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: aurRow.modelData.name + ", " + stateChip.text
                        Accessible.description: Updates.aurReadOnly ? "Read-only. Open its AUR page. More in its menu." : "Review the changes. More in its menu."
                        Accessible.onPressAction: up.openAurRow(aurRow)
                        Component.onCompleted: if (up.menuOf === modelData.name) Qt.callLater(() => aurMenu.popup(aurRow.width * 0.55, aurRow.height / 2))
                        ContextMenu {
                            id: aurMenu
                            target: aurRow
                            bounds: up
                            title: aurRow.modelData.name
                            ContextMenuLabel { text: aurRow.modelData.name + "  " + aurRow.modelData.new }
                            ContextMenuItem { text: "Review changes"; glyph: "\u{f0208}"; shortcut: "↵"; visible: !Updates.aurReadOnly; onTriggered: up.openAurRow(aurRow) }
                            ContextMenuCheckboxItem {
                                text: "Include in this update"
                                shortcut: "Space"
                                enabled: Updates.selectable(aurRow.modelData.name)
                                checked: Updates.selected(aurRow.modelData.name)
                                onToggled: on => Updates.setExcluded(aurRow.modelData.name, !on)
                            }
                            ContextMenuSeparator {}
                            ContextMenuItem {
                                text: "Approve this version"
                                glyph: "\u{f012c}"
                                visible: aurRow.st === "review" && !!aurRow.rv && !aurRow.rv.error
                                onTriggered: Updates.approve(aurRow.modelData.name)
                            }
                            ContextMenuItem {
                                text: "Withdraw approval"
                                visible: aurRow.st === "approved"
                                onTriggered: Updates.unapprove(aurRow.modelData.name)
                            }
                            ContextMenuCheckboxItem {
                                text: "Trust its future updates"
                                visible: !Updates.aurReadOnly
                                checked: Updates.trusted.indexOf(aurRow.modelData.name) >= 0
                                onToggled: on => Updates.setTrusted(aurRow.modelData.name, on)
                            }
                            ContextMenuSeparator {}
                            ContextMenuItem { text: "Open on the AUR"; glyph: "\u{f03cc}"; enabled: aurRow.page !== ""; onTriggered: Apps.open(aurRow.page) }
                            ContextMenuCheckboxItem { text: "Hold at " + aurRow.modelData.old; checked: Updates.isHeld(aurRow.modelData.name); onToggled: on => Updates.setHeld(aurRow.modelData.name, on) }
                            ContextMenuItem { text: "Copy name"; glyph: "\u{f018f}"; onTriggered: Clipboard.copyText(aurRow.modelData.name) }
                        }
                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Include " + aurRow.modelData.name
                            enabled: Updates.selectable(aurRow.modelData.name)
                            on: Updates.selected(aurRow.modelData.name)
                            opacity: enabled ? 1 : 0.35
                            onToggled: Updates.setExcluded(aurRow.modelData.name, Updates.selected(aurRow.modelData.name))
                        }
                        Column {
                            id: aurWords
                            x: 56; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56 - stateChip.width - 40
                            spacing: 1
                            Label { width: parent.width; elide: Text.ElideRight; text: aurRow.modelData.name; size: Theme.tBody; weight: Theme.wMedium }
                            Version { from: aurRow.modelData.old; to: aurRow.modelData.new }
                        }
                        Chip {
                            id: stateChip
                            anchors { right: chev.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            readonly property var look: {
                                const s = aurRow.st, r = aurRow.rv;
                                if (Updates.isHeld(aurRow.modelData.name)) return ["Held at " + aurRow.modelData.old, Theme.textSecondary, ""];
                                if (Updates.aurReadOnly) return ["Read-only", Theme.textSecondary, ""];
                                if (s === "trusted") return ["Trusted", Theme.accent, "\u{f0565}"];
                                if (s === "approved") return [Updates.autoApproved.indexOf(aurRow.modelData.name) >= 0 ? "Version bump · auto" : "Approved", Theme.green, "\u{f012c}"];
                                if (s === "loading" || !r) return ["Reading…", Theme.textSecondary, ""];   // tertiary read 3.7:1 on a row
                                if (r.error) return ["Couldn't read", Theme.red, ""];
                                if (r.firstTime) return ["New to you · review", Theme.orange, "\u{f0026}"];
                                if (r.flags && r.flags.length) return [r.flags.length + " to look at", Theme.orange, "\u{f0026}"];
                                if (r.routine) return ["Version bump · review", Theme.green, ""];
                                return ["Changed · review", Theme.textSecondary, ""];
                            }
                            text: look[0]; tone: look[1]; glyph: look[2]
                        }
                        Text { id: chev; textFormat: Text.PlainText; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: "\u{f0142}"; font.family: Theme.fontGlyph; font.pixelSize: 15; color: Theme.textTertiary }
                    }
                }
            }

            // Flatpak apps: sandboxed and signed, each updates on its own.
            Card {
                visible: Updates.flatpak.length > 0
                Item {
                    width: parent.width; height: Math.max(Theme.sp(34), fpHead.implicitHeight)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f08c4}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphM; color: Theme.accent }
                    Column {
                        id: fpHead
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Label { text: "Flatpak · " + Updates.flatpak.length + (Updates.flatpak.length === 1 ? " update" : " updates"); size: Theme.tCallout; weight: Theme.wSemibold }
                        Label { text: "Sandboxed and signed: pick any, no review needed"; size: Theme.tFootnote; color: Theme.textTertiary }
                    }
                }
                Repeater {
                    model: Updates.flatpak
                    Item {
                        id: fpRow
                        required property var modelData
                        required property int index
                        readonly property bool chosen: !Updates.flatpakOff[modelData.id]
                        width: parent.width; height: Math.max(Theme.sp(42), fpWords.implicitHeight + Theme.s2)
                        Rectangle { visible: fpRow.index > 0; width: parent.width; height: 1; color: Theme.cardEdge }
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            if (fpMenu.handleKey(e)) return;
                            if (e.key === Qt.Key_Space) { Updates.setFlatpakOff(fpRow.modelData.id, fpRow.chosen); e.accepted = true; }
                        }
                        FocusRing { cornerRadius: Theme.r1 }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: fpRow.modelData.name + (fpRow.chosen ? ", included" : ", left out")
                        ContextMenu {
                            id: fpMenu
                            target: fpRow
                            bounds: up
                            title: fpRow.modelData.name
                            ContextMenuLabel { text: fpRow.modelData.name }
                            ContextMenuCheckboxItem { text: "Include in this update"; shortcut: "Space"; checked: fpRow.chosen; onToggled: on => Updates.setFlatpakOff(fpRow.modelData.id, !on) }
                            ContextMenuSeparator {}
                            ContextMenuItem { text: "Copy app ID"; glyph: "\u{f018f}"; onTriggered: Clipboard.copyText(fpRow.modelData.app || fpRow.modelData.id) }
                        }
                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Include " + fpRow.modelData.name
                            on: fpRow.chosen
                            onToggled: Updates.setFlatpakOff(fpRow.modelData.id, !Updates.flatpakOff[fpRow.modelData.id])
                        }
                        Column {
                            id: fpWords
                            x: 56; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56
                            spacing: 1
                            Label {
                                width: parent.width; elide: Text.ElideRight; size: Theme.tBody; weight: Theme.wMedium
                                text: fpRow.modelData.name + "  ·  " + (fpRow.modelData.app || fpRow.modelData.id)
                                    + (fpRow.modelData.runtime ? "  ·  runtime" : "") + (fpRow.modelData.install === "system" ? "  ·  system-wide" : "")
                            }
                            Version { visible: fpRow.modelData.old !== ""; from: fpRow.modelData.old; to: fpRow.modelData.new }
                        }
                    }
                }
            }

            Button {
                glyph: "\u{f03d6}"
                text: "Your packages"
                onClicked: up.go("pkgs")
            }

            Item { width: 1; height: 4 }
        }
    }
    PackagesView {
        id: pkgView
        visible: up.view === "pkgs"
        opacity: up.view === "pkgs" ? up.enter : 0
        x: (1 - up.enter) * 14
        width: parent.width; height: parent.height
        focus: visible
    }
    // Both follow the list's own visibility: never bind their `visible` (an
    // override showed ScrollFade's mask, a black rectangle, over the list).
    ScrollFade { flickable: listFlick }
    ScrollHint { flickable: listFlick; anchors { right: parent.right; top: listFlick.top; bottom: listFlick.bottom; rightMargin: 4 } }

    // Footer: what will happen, and the button.
    Item {
        id: listFoot
        visible: up.view === "list" && Updates.total > 0
        opacity: up.enter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 22; rightMargin: 22; bottomMargin: 18 }
        height: visible ? footBtns.implicitHeight : 0
        Label {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; right: footBtns.left; rightMargin: 12 }
            elide: Text.ElideRight
            text: Updates.waitingReview > 0
                ? Updates.waitingReview + " AUR " + (Updates.waitingReview === 1 ? "package waits" : "packages wait") + " for your review"
                : Updates.aurReadOnly && Updates.chosenCount === 0 ? ""
                : "Sleep and shutdown wait until it's done"
            size: Theme.tFootnote; color: Theme.textTertiary
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
            width: parent.width - 44; height: Math.max(Theme.sp(44), rvTitle.implicitHeight)
            Column {
                id: rvTitle
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
                    readonly property string page: reviewView.r ? Links.webLink(reviewView.r.url) : ""
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{f03cc}"; text: "AUR"
                    enabled: page !== ""
                    onClicked: Apps.open(page)
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
                    Label { text: modelData.sha; size: Theme.tFootnote; font.family: Theme.fontMono; color: Theme.accent }
                    Label { text: modelData.subject; size: Theme.tSub; color: Theme.textSecondary; width: Math.min(implicitWidth, rvInfo.width - 260); elide: Text.ElideRight }
                    Label { text: modelData.author + " · " + modelData.when; size: Theme.tFootnote; color: Theme.textTertiary }
                }
            }
            // Its standing in the AUR: how many use it, who keeps it, how old.
            Row {
                readonly property var c: reviewView.r ? reviewView.r.community : null
                visible: !!c
                spacing: 6
                Chip {
                    id: standing
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
                    width: rvInfo.width - standing.width - 6
                    wrapMode: Text.Wrap
                    size: Theme.tFootnote; color: Theme.textTertiary
                }
            }
            Flow {
                width: parent.width
                spacing: 6
                visible: !!(reviewView.r && reviewView.r.flags && reviewView.r.flags.length)
                Repeater {
                    model: reviewView.r && reviewView.r.flags ? reviewView.r.flags : []
                    // A line worth a look: pressing it shows that line (a Button, not a
                    // clickable Chip; its mark keeps the flag's orange).
                    Button {
                        required property var modelData
                        kind: "quiet"
                        size: Theme.tFootnote
                        tone: Theme.orange; glyph: "\u{f0026}"
                        text: modelData.why + " · " + modelData.path + ":" + modelData.line
                        label: modelData.why + ", " + modelData.path + " line " + modelData.line
                        onClicked: {
                            const i = reviewView.r.files.findIndex(f => f.path === modelData.path);
                            if (i >= 0) up.fileIx = i;
                            Qt.callLater(() => diff.scrollToLine(modelData.line));
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
            radius: Theme.r2
        }
        Notice {
            visible: !!(reviewView.r && reviewView.r.error)
            anchors { top: diff.top; left: diff.left; right: diff.right }
            glyph: "\u{f0026}"; tone: Theme.red
            title: "Couldn't review this package"
            detail: reviewView.r ? (reviewView.r.error || "") : ""
            action: "Retry"
            onActed: Updates.review(up.pkg, true)
        }

        Item {
            id: rvFoot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 22; rightMargin: 22; bottomMargin: 18 }
            height: Theme.sp(34)
            Label {
                visible: Updates.mutationError !== ""
                text: Updates.mutationError
                color: Theme.orange
                anchors { bottom: parent.top; bottomMargin: 8 }
                size: Theme.tSub
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Trust " + up.pkg
                    on: Updates.trusted.indexOf(up.pkg) >= 0
                    onToggled: Updates.setTrusted(up.pkg, !on)
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label { text: "Trust " + up.pkg; size: Theme.tSub; weight: Theme.wMedium }
                    Label { text: "Skip reviewing its future updates"; size: Theme.tFootnote; color: Theme.textTertiary }
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
                    enabled: !!reviewView.r && !reviewView.r.error && (up.installing ? !Updates.running && Updates.installPending === "" : !done)
                    glyph: done && !up.installing ? "\u{f012c}" : ""
                    text: up.installing ? (done ? "Install" : "Approve and install") : done ? "Approved" : "Approve this change"
                    onClicked: up.approveHere()
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
            width: parent.width; height: Math.max(44, runHead.implicitHeight)
            Rectangle {
                id: runBadge
                width: 44; height: 44; radius: Theme.r4
                color: Updates.running ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                     : runCol.ok ? Qt.rgba(0.19, 0.82, 0.35, 0.18) : Qt.rgba(1, 0.62, 0.04, 0.18)
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: Updates.running ? "\u{f06b0}" : runCol.ok ? "\u{f012c}" : "\u{f0026}"
                    font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphM   // in a status disc, as its siblings (it was 20)
                    color: Updates.running ? Theme.accent : runCol.ok ? Theme.green : Theme.orange
                    RotationAnimation on rotation { running: Updates.running && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                }
            }
            Column {
                id: runHead
                x: 56; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 56
                spacing: 2
                Label {
                    text: Updates.running ? "Updating" : runCol.ok ? "All done" : (runCol.res && runCol.res.cancelled) ? "Cancelled"
                        : (runCol.res && runCol.res.unknown) ? "Update stopped" : (runCol.res && runCol.res.partial) ? "Partly done"
                        : "Finished, with things to look at"
                    size: Theme.tTitle3; weight: Theme.wSemibold
                }
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: Updates.running ? Updates.phaseLabel
                        : Updates.runError || (runCol.res ? [runCol.res.repo ? "Arch packages updated" : "", runCol.res.installed && runCol.res.installed.length ? runCol.res.installed.length + " AUR installed" : ""].filter(x => x).join(" · ") : "")
                    size: Theme.tSub; color: Updates.runError ? Theme.orange : Theme.textTertiary
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
                        textFormat: Text.PlainText
                        width: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.now ? "\u{f0997}" : parent.seen ? "\u{f012c}" : parent.skipped ? "\u{f0374}" : "\u{f0766}"
                        font.family: Theme.fontGlyph; font.pixelSize: 13
                        color: parent.now ? Theme.accent : parent.seen ? Theme.green : Theme.textTertiary
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: modelData.label + (parent.skipped ? " · skipped" : ""); size: Theme.tBody; weight: parent.now ? Theme.wSemibold : Theme.wRegular; color: parent.seen || parent.now ? Theme.textPrimary : Theme.textTertiary }
                }
            }
        }

        // The current line, then the log on request.
        Label {
            visible: Updates.running && !up.showLog
            width: parent.width; elide: Text.ElideRight
            text: Updates.currentLine
            size: Theme.tFootnote; font.family: Theme.fontMono; color: Theme.textTertiary
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
            title: Updates.helperState !== "failed" ? "Asked for your password " + (runCol.res ? runCol.res.prompts : 0) + " times"
                 : Updates.helperError ? "Not set up" : "Not set up (cancelled?)"
            detail: Updates.helperState === "failed" && Updates.helperError ? Updates.helperError
                  : "Set up once (your password one more time) and every update after asks just once."
            detailLines: 8
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
            width: parent.width; height: 190; radius: Theme.r2
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
