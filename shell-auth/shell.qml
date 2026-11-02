// kuwai's password prompt (the polkit authentication agent), grown out of the
// island.
//
// It runs as its own small process (rice-auth.service), not inside the main
// shell: nothing untrusted (notifications, clipboard previews, web content)
// shares memory with what you type, and a reload or crash of the shell never
// cancels an authentication. To still *be* the island, it starts exactly
// where the island rests on your screen (the shell publishes that shape to
// $XDG_RUNTIME_DIR/rice/island.json), in the same glass and the same springs,
// grows into the card, and folds back into the island when it's done. Tokens,
// type and the theme's accent come from the shell's own config/ and
// components/ (symlinked; they read files only, no services).
//
// Security:
//   · the password goes from the field straight to polkit's own checker
//     (AuthFlow.submit → polkit-agent-helper-1, a system socket service); this
//     code never stores, logs or forwards it, and the field is wiped on
//     submit, cancel and close
//   · it says what is asking: polkit's message, the action id, and whose
//     password; it answers as *you* when polkit offers several admins
//   · tries left and the lockout come from pam_faillock (`faillock`, your own
//     record, read-only); a cancel counts as a try there, so it says so
//   · Overlay layer, exclusive keyboard, dimmed screen: nothing sits above it
//     or takes the keyboard while it's up; the lock screen still covers it
//   · no crash handler or core dumps (see systemd/rice-auth.service); exits 3
//     if another agent owns the session, and systemd falls back to KDE's
//
// Keys: ↵ authenticate · Esc cancel.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.config
import qs.components

ShellRoot {
    id: root

    // ── The request ──────────────────────────────────────────────────────
    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: root.begin()
        onIsActiveChanged: if (!isActive && !root.succeeded) root.finish()
        // A queued request becomes the current one while we're closed.
        onFlowChanged: if (flow && !root.open && !hold.running) root.begin()
    }
    readonly property var flow: agent.flow

    // A snapshot, so the card keeps its words while it folds away after the
    // request is gone.
    property bool open: false
    property string screenName: ""
    property string message: ""
    property string actionId: ""
    property string who: ""
    property string promptText: ""
    property bool echo: false
    property bool busy: false
    property bool wrong: false
    property bool succeeded: false
    property bool switching: false
    property bool caps: false
    readonly property string me: Quickshell.env("USER") || ""

    function begin() {
        const f = agent.flow;
        succeeded = false; wrong = false; busy = false;
        message = f ? (f.message || "") : "";
        actionId = f ? (f.actionId || "") : "";
        selectMe();
        syncPrompt();
        faillock.running = true;
        capsProbe.running = true;
        where.running = true;               // which screen you're on, then open
    }
    function finish() {
        open = false;
        busy = false;
        pendingFile.setText("");
        // Another request was waiting behind this one: bring it up (it used to
        // stay invisible until something else woke the agent).
        Qt.callLater(() => { if (agent.flow && !agent.flow.isCompleted && !root.open) root.begin(); });
    }
    // "A password is needed" for the island (every screen shows a lock chip
    // until it's answered; clicking it brings this prompt to that screen).
    // Only what is asking goes in this file, never anything typed.
    FileView { id: pendingFile; path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/auth-pending"; printErrors: false }
    onOpenChanged: if (open) pendingFile.setText(describe(actionId) + "\n" + screenName + "\n")
    // The island asks for the prompt on another screen: move it there.
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/auth-summon"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const n = text().trim();
            if (root.open && n && Quickshell.screens.some(s => s.name === n) && n !== root.screenName) {
                root.screenName = n;
                pendingFile.setText(root.describe(root.actionId) + "\n" + n + "\n");
            }
        }
    }
    function syncPrompt() {
        const f = agent.flow;
        if (!f) return;
        const id = f.selectedIdentity;
        who = id && id.string ? id.string : me;
        promptText = (f.inputPrompt || "").replace(/[\s:]+$/, "");
        echo = !!f.responseVisible;
    }
    // Polkit lists every admin and picks the first (often root): answer as
    // you. Switching restarts PAM, which polkit reports as a failure; that one
    // is swallowed. (From DankMaterialShell's agent.)
    function selectMe() {
        const f = agent.flow;
        if (!f || !f.identities || f.identities.length < 2 || !me) return;
        for (let i = 0; i < f.identities.length; i++) {
            const id = f.identities[i];
            if (id && !id.isGroup && id.string === me) {
                if (id !== f.selectedIdentity) { switching = true; f.selectedIdentity = id; switching = false; }
                return;
            }
        }
    }
    function submit(value) {
        const f = agent.flow;
        if (!f || !f.isResponseRequired || !value || busy || lockLeft > 0) return false;
        busy = true;
        wrong = false;
        f.submit(value);
        return true;
    }
    function cancel() {
        const f = agent.flow;
        if (f && !f.isCompleted) f.cancelAuthenticationRequest();
        finish();
    }
    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            if (root.switching) return;
            root.wrong = true;
            root.busy = false;
            faillock.running = true;
        }
        function onAuthenticationSucceeded() {
            root.succeeded = true;
            root.busy = false;
            hold.restart();
        }
        function onAuthenticationRequestCancelled() { root.finish(); }
        function onIsResponseRequiredChanged() { root.syncPrompt(); if (root.flow && root.flow.isResponseRequired) root.busy = false; }
        function onInputPromptChanged() { root.syncPrompt(); }
        function onResponseVisibleChanged() { root.syncPrompt(); }
        function onSelectedIdentityChanged() { root.syncPrompt(); }
    }
    // A beat on the check mark before folding away.
    Timer { id: hold; interval: 520; onTriggered: root.finish() }

    // Never without an agent: exit 3 lets systemd start KDE's instead.
    Timer {
        interval: 6000; running: true
        onTriggered: if (!agent.isRegistered) { console.warn("rice-auth: another polkit agent owns this session"); Qt.exit(3); }
    }

    // ── Which screen (Hyprland's word; Quickshell's can be stale) ────────
    Process {
        id: where
        // The screen you're looking at (kuwai.where(): pointer and focus agree,
        // or you just typed → the focused one, else the pointer's).
        command: ["hyprctl", "repl", "return kuwai.where()"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = "";
                try { const w = JSON.parse(text.trim().split("\n").pop()); name = w.looking || w.focused || ""; } catch (e) {}
                if (!Quickshell.screens.some(s => s.name === name))
                    name = Quickshell.screens.length ? Quickshell.screens[0].name : "";
                root.screenName = name;
                root.open = !!agent.flow;
            }
        }
    }
    Process {
        id: capsProbe
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.caps = JSON.parse(text).keyboards.some(k => k.main && k.capsLock); } catch (e) {}
            }
        }
    }

    // ── Tries left (pam_faillock) ────────────────────────────────────────
    // Arch's defaults: 3 failures within 15 minutes lock the account for 10.
    property int deny: 3
    property int failInterval: 900
    property int unlockTime: 600
    property int fails: 0
    property real lockedUntil: 0
    property real now: Date.now()
    readonly property int left: Math.max(0, deny - fails)
    readonly property int lockLeft: Math.max(0, Math.ceil((lockedUntil - now) / 1000))
    Timer { interval: 1000; repeat: true; running: root.open && root.lockedUntil > root.now; onTriggered: root.now = Date.now() }
    FileView {
        path: "/etc/security/faillock.conf"
        printErrors: false
        onLoaded: {
            const get = k => { const m = text().match(new RegExp("^\\s*" + k + "\\s*=\\s*(\\d+)", "m")); return m ? parseInt(m[1]) : -1; };
            if (get("deny") > 0) root.deny = get("deny");
            if (get("fail_interval") > 0) root.failInterval = get("fail_interval");
            if (get("unlock_time") >= 0) root.unlockTime = get("unlock_time");
        }
    }
    Process {
        id: faillock
        command: ["faillock", "--user", root.me]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = Date.now();
                let n = 0, last = 0;
                for (const l of text.split("\n")) {
                    const m = l.match(/^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d)\s+\S+\s+\S+\s+V\s*$/);
                    if (!m) continue;
                    const at = new Date(m[1] + "T" + m[2]).getTime();
                    if (t - at <= root.failInterval * 1000) { n++; last = Math.max(last, at); }
                }
                root.now = t;
                root.fails = n;
                root.lockedUntil = n >= root.deny && root.unlockTime > 0 ? last + root.unlockTime * 1000 : 0;
            }
        }
    }

    // ── The island's resting shape, per screen (published by the shell) ──
    property var shapes: ({})
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/island.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.shapes = JSON.parse(text()).screens || {}; } catch (e) {} }
    }

    function describe(id) {
        const m = {
            "org.freedesktop.policykit.exec": "Run as administrator",
            "org.freedesktop.packagekit.package-install": "Install software",
            "org.freedesktop.packagekit.system-update": "Update the system",
            "org.freedesktop.udisks2.filesystem-mount-system": "Mount a drive",
            "org.freedesktop.udisks2.encrypted-unlock-system": "Unlock an encrypted drive",
            "org.freedesktop.NetworkManager.settings.modify.system": "Change network settings",
            "org.freedesktop.login1.reboot-multiple-sessions": "Restart while others are signed in",
            "org.freedesktop.login1.power-off-multiple-sessions": "Shut down while others are signed in",
            "org.freedesktop.systemd1.manage-units": "Manage a system service",
            "org.freedesktop.timedate1.set-time": "Change the date and time",
            "org.freedesktop.hostname1.set-hostname": "Rename this computer"
        };
        if (id === "org.freedesktop.policykit.exec" && /\/usr\/bin\/pacman\b/.test(root.message))
            return /pacman -U\b/.test(root.message) ? "Install AUR updates" : "Install system updates";
        return m[id] || "Administrator access";
    }
    // Your picture (~/.face), as a round PNG in the runtime dir.
    property string facePng: ""
    readonly property string faceOut: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/face.png"
    Process {
        running: true
        command: ["sh", "-c", 'f="$HOME/.face"; o="$1"; [ -r "$f" ] || exit 1; [ "$o" -nt "$f" ] && { echo ok; exit; }; m="$o.mask.png"; magick -size 132x132 xc:none -fill white -draw "circle 66,66 66,0" "png:$m" && magick "$f[0]" -resize 132x132^ -gravity center -extent 132x132 "$m" -compose DstIn -composite "png:$o"; rm -f "$m"; [ -s "$o" ] && echo ok', "face", root.faceOut]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "ok") root.facePng = root.faceOut }
    }
    function mmss(s) { return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    // Text on the accent: dark on light accents, white on dark ones.
    function onAccent(c) { return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.55 ? "#111114" : "#ffffff"; }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            readonly property bool here: root.open && root.screenName === modelData.name
            readonly property var rest: root.shapes[modelData.name] || ({ w: 210, h: 34, top: 6, notch: false })
            visible: here || g.value > 0.002
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rice-auth"
            WlrLayershell.keyboardFocus: here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            onHereChanged: {
                field.text = "";
                if (here) field.forceActiveFocus();
            }

            // The island's own springs (IslandBar: grow 300/34.6, shrink 380/39).
            Spring {
                id: g
                tier: win.here ? (Theme.reduceMotion ? Theme.springFast : ({ stiffness: 300, damping: 34.6 }))
                               : (Theme.reduceMotion ? Theme.springFast : ({ stiffness: 380, damping: 39 }))
                epsilon: 0.001
                target: win.here ? 1 : 0
            }
            readonly property real p: Math.max(0, Math.min(1.08, g.value))

            // The screen dims (it isn't clickable meanwhile).
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.36 * Math.min(1, win.p))
                MouseArea { anchors.fill: parent; enabled: win.here }
            }

            // Soft shadow (plain rectangles: this process renders in software).
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    readonly property real spread: 4 + index * 7
                    x: card.x - spread + shake.x; y: card.y - spread + 10 + index * 3
                    width: card.width + spread * 2; height: card.height + spread * 2
                    radius: card.radius + spread
                    color: Qt.rgba(0, 0, 0, 0.07 * Math.min(1, win.p) * card.opacity)
                }
            }

            Item {
                id: card
                readonly property real fullW: 432
                readonly property real fullH: content.implicitHeight + 44
                width: win.rest.w + (fullW - win.rest.w) * win.p
                height: win.rest.h + (fullH - win.rest.h) * win.p
                x: Math.round((win.width - width) / 2)
                y: win.rest.top
                readonly property real radius: Math.min(height / 2, win.rest.h / 2 + (30 - win.rest.h / 2) * Math.min(1, win.p))
                // Fades in over the island's first moves (so the island's own
                // content goes under it smoothly) and out as it lands back.
                opacity: Math.min(1, win.p * 5)
                transform: Translate { id: shake; x: 0 }
                clip: win.p < 0.98            // nothing spills past the shape while it grows

                GlassCard {
                    visible: !win.rest.notch
                    anchors.fill: parent
                    radius: card.radius
                    tint: Qt.rgba(0, 0, 0, 0.9)
                }
                // The notch style: the same shape as the island, ears and all
                // (IslandBar: radius 14 at rest, 30 grown).
                NotchShape {
                    visible: win.rest.notch
                    x: -ear
                    w: card.width; h: card.height
                    ear: 9
                    radius: 14 + 16 * Math.min(1, win.p)
                    fill: Qt.rgba(0, 0, 0, 0.94)
                }

                SequentialAnimation {
                    id: shaker
                    NumberAnimation { target: shake; property: "x"; to: -10; duration: 55; easing.type: Easing.OutQuad }
                    NumberAnimation { target: shake; property: "x"; to: 9; duration: 75; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: shake; property: "x"; to: -6; duration: 70; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: shake; property: "x"; to: 3; duration: 60; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: shake; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
                }
                Connections {
                    target: root
                    function onWrongChanged() {
                        if (!root.wrong || !win.here) return;
                        field.text = "";
                        if (!Theme.reduceMotion) shaker.restart();
                        field.forceActiveFocus();
                    }
                }

                Column {
                    id: content
                    x: 22; y: 22
                    width: card.fullW - 44
                    spacing: 0
                    // Content arrives once the shape is mostly there, and leaves first.
                    opacity: win.here ? Math.max(0, Math.min(1, (win.p - 0.55) / 0.4))
                                      : Math.max(0, Math.min(1, (win.p - 0.7) / 0.3))
                    transform: Translate { y: (1 - content.opacity) * 6 }

                    // Who and what
                    Row {
                        width: parent.width
                        spacing: 14
                        Item {
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent
                                radius: 22
                                color: Qt.rgba(1, 1, 1, 0.1)
                                // ~/.face, cut round once by magick (this process
                                // renders in software, which can't clip to a circle).
                                Image {
                                    id: face
                                    anchors.fill: parent
                                    source: root.facePng ? "file://" + root.facePng : ""
                                    sourceSize: Qt.size(88, 88)
                                    asynchronous: true
                                    cache: false
                                }
                                Text {
                                    visible: face.status !== Image.Ready
                                    anchors.centerIn: parent
                                    text: (root.who || "?").charAt(0).toUpperCase()
                                    font.family: Theme.fontRounded; font.pixelSize: 19; font.weight: Theme.wSemibold
                                    color: Theme.textPrimary
                                }
                            }
                            // The lock badge, in the theme's accent.
                            Rectangle {
                                anchors { right: parent.right; bottom: parent.bottom; rightMargin: -3; bottomMargin: -3 }
                                width: 20; height: 20; radius: 10
                                color: "#0b0b0d"
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 16; height: 16; radius: 8
                                    color: root.succeeded ? Theme.green : Theme.accent
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.succeeded ? "\u{f012c}" : "\u{f033e}"
                                        font.family: Theme.fontGlyph; font.pixelSize: 10
                                        color: root.succeeded ? "#0b0b0d" : root.onAccent(Theme.accent)
                                    }
                                }
                            }
                        }
                        Column {
                            width: parent.width - 58
                            spacing: 3
                            anchors.verticalCenter: parent.verticalCenter
                            Label {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.succeeded ? "Done" : root.describe(root.actionId)
                                size: 16; weight: Theme.wSemibold
                            }
                            Label {
                                width: parent.width
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                text: root.message
                                size: 12; color: Theme.textSecondary
                            }
                        }
                    }

                    Item { width: 1; height: 18 }

                    // Password
                    Rectangle {
                        id: box
                        width: parent.width; height: 44; radius: 22
                        color: Qt.rgba(1, 1, 1, field.activeFocus ? 0.09 : 0.06)
                        border.width: 1
                        border.color: root.wrong ? Qt.rgba(1, 0.27, 0.23, 0.7)
                                    : field.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.75)
                                    : Qt.rgba(1, 1, 1, 0.08)
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        opacity: root.lockLeft > 0 ? 0.5 : 1

                        Text {
                            id: keyGlyph
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            text: "\u{f0306}"
                            font.family: Theme.fontGlyph; font.pixelSize: 15
                            color: Theme.textTertiary
                        }
                        TextInput {
                            id: field
                            anchors { left: keyGlyph.right; leftMargin: 10; right: capsTag.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            height: parent.height
                            verticalAlignment: TextInput.AlignVCenter
                            enabled: !root.busy && !root.succeeded && root.lockLeft === 0
                            // Nothing on screen says how long it is (a dot per
                            // character tells anyone watching or recording the
                            // length): no echo at all, like a terminal; the
                            // dots below only pulse once per keystroke.
                            echoMode: root.echo ? TextInput.Normal : TextInput.NoEcho
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText | Qt.ImhNoAutoUppercase
                            font.family: Theme.fontText
                            font.pixelSize: 15
                            onTextChanged: if (!root.echo && text.length) keyPulse.hit()
                            color: Theme.textPrimary
                            selectByMouse: false
                            focus: true
                            Keys.onReturnPressed: win.submit()
                            Keys.onEnterPressed: win.submit()
                            Keys.onEscapePressed: root.cancel()
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_CapsLock) { root.caps = !root.caps; capsProbe.running = true; }
                            }
                            // Typing feedback that gives nothing away: always
                            // five dots, a wave runs across them on each key.
                            Row {
                                visible: !root.echo && !!field.text
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Repeater {
                                    model: 5
                                    Rectangle {
                                        id: dot
                                        required property int index
                                        width: 7; height: 7; radius: 3.5
                                        color: Theme.textPrimary
                                        opacity: 0.55
                                        SequentialAnimation {
                                            id: wave
                                            PauseAnimation { duration: dot.index * 28 }
                                            ParallelAnimation {
                                                NumberAnimation { target: dot; property: "opacity"; to: 1; duration: 90; easing.type: Easing.OutQuad }
                                                NumberAnimation { target: dot; property: "scale"; to: 1.25; duration: 90; easing.type: Easing.OutQuad }
                                            }
                                            ParallelAnimation {
                                                NumberAnimation { target: dot; property: "opacity"; to: 0.55; duration: 220; easing.type: Easing.OutCubic }
                                                NumberAnimation { target: dot; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                            }
                                        }
                                        Connections { target: keyPulse; function onHit() { if (!Theme.reduceMotion) wave.restart(); } }
                                    }
                                }
                            }
                            // (only a trigger for the dots' wave)
                            QtObject { id: keyPulse; signal hit() }
                            Label {
                                visible: !field.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.lockLeft > 0 ? "Locked" : (root.promptText && !/^password$/i.test(root.promptText) ? root.promptText : "Password for " + root.who)
                                size: 14; color: Theme.textTertiary
                            }
                        }
                        // Caps Lock on: say so where you're looking.
                        Rectangle {
                            id: capsTag
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: root.caps ? capsRow.implicitWidth + 16 : 0
                            height: 28; radius: 14
                            visible: width > 0
                            color: Qt.rgba(1, 0.62, 0.04, 0.16)
                            clip: true
                            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                            Row {
                                id: capsRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0632}"; font.family: Theme.fontGlyph; font.pixelSize: 12; color: Theme.orange }
                                Label { anchors.verticalCenter: parent.verticalCenter; text: "Caps Lock"; size: 11; weight: Theme.wMedium; color: Theme.orange }
                            }
                        }
                        // Checking: a quiet sweep along the bottom edge.
                        Rectangle {
                            visible: root.busy
                            anchors { bottom: parent.bottom; bottomMargin: 1 }
                            height: 2; radius: 1
                            width: parent.width * 0.28
                            color: Theme.accent
                            SequentialAnimation on x {
                                running: root.busy && !Theme.reduceMotion
                                loops: Animation.Infinite
                                NumberAnimation { from: 22; to: box.width * 0.72 - 22; duration: 620; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: box.width * 0.72 - 22; to: 22; duration: 620; easing.type: Easing.InOutQuad }
                            }
                        }
                    }

                    Item { width: 1; height: 10 }

                    // Tries left, the lockout, PAM's own words.
                    Label {
                        id: note
                        width: parent.width
                        leftPadding: 16
                        wrapMode: Text.Wrap
                        size: 12
                        readonly property string pam: root.flow && root.flow.supplementaryMessage ? root.flow.supplementaryMessage : ""
                        text: {
                            if (root.lockLeft > 0) return `Too many tries. Locked for ${root.mmss(root.lockLeft)}.`;
                            if (pam && root.flow.supplementaryIsError) return pam;
                            const n = root.left;
                            const tries = n === 1 ? "1 try left" : `${n} tries left`;
                            if (root.wrong) return n === 1 ? `Wrong password · last try before a ${Math.round(root.unlockTime / 60)}-minute lock` : `Wrong password · ${tries}`;
                            if (n === 1) return `Last try before a ${Math.round(root.unlockTime / 60)}-minute lock · cancelling counts too`;
                            return pam || `${tries} · cancelling counts as one`;
                        }
                        color: root.lockLeft > 0 || root.wrong ? Theme.red
                             : root.left === 1 ? Theme.orange
                             : Theme.textTertiary
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    Item { width: 1; height: 18 }

                    // Actions
                    Item {
                        width: parent.width; height: 36
                        Label {
                            anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter; right: buttons.left; rightMargin: 12 }
                            elide: Text.ElideMiddle
                            text: root.actionId
                            font.family: Theme.fontMono
                            size: 10; color: Qt.rgba(1, 1, 1, 0.32)
                        }
                        Row {
                            id: buttons
                            anchors.right: parent.right
                            spacing: 8
                            RaisedButton { width: 96; height: 36; kind: "secondary"; text: "Cancel"; onClicked: root.cancel() }
                            RaisedButton {
                                width: 128; height: 36
                                enabled: !!field.text && !root.busy && root.lockLeft === 0
                                text: root.busy ? "Checking…" : "Authenticate"
                                onClicked: win.submit()
                            }
                        }
                    }
                }
            }

            function submit() {
                const v = field.text;
                field.text = "";              // the field never keeps it
                if (!root.submit(v)) field.forceActiveFocus();
            }
        }
    }
}
