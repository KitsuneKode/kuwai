pragma Singleton

// Where sound really goes. With EasyEffects the default output is its
// virtual sink ("Easy Effects Sink"), and EasyEffects feeds one real device
// (the Audiocular D07 or the FiiO JA11, the Cadenza behind either). Naming
// the default called every DAC "Easy Effects Sink"; this follows EasyEffects'
// last stage (ee_soe_*) to the device it is linked to.
//
//   AudioRoute.sink      the default output (what volume keys change)
//   AudioRoute.output    the device that plays: the one behind EasyEffects, else the default
//   AudioRoute.effects   true while EasyEffects sits in between
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool effects: !!sink && /^easyeffects_sink$/.test(sink.name || "")
    // EasyEffects' output stage, linked to a hardware sink. A filter node
    // that's linked onward to another filter isn't it: only a real sink.
    readonly property var behind: {
        if (!effects) return null;
        for (const g of Pipewire.linkGroups.values) {
            const s = g.source, t = g.target;
            if (!s || !t || !/^ee_soe_/.test(s.name || "")) continue;
            if (t.type === PwNodeType.AudioSink && !/^(easyeffects|ee_)/.test(t.name || "")) return t;
        }
        return null;
    }
    // EasyEffects unlinks itself a few seconds after the last stream stops
    // (outputInactivityTimeout): then the device it was set to, from its
    // own settings, is still where sound will go.
    property string configured: ""
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/easyeffects/db/easyeffectsrc"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const m = /^\[StreamOutputs\][^[]*?^outputDevice=(.+)$/m.exec(text());
            root.configured = m ? m[1].trim() : "";
        }
    }
    readonly property var idleBehind: effects && !behind && configured
        ? Pipewire.nodes.values.find(n => n.name === configured && n.type === PwNodeType.AudioSink) || null : null
    readonly property var output: behind || idleBehind || sink
    PwObjectTracker { objects: [root.sink, root.output].filter(n => n) }
}
