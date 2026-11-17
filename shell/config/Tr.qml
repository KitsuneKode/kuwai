pragma Singleton
// (pragma first: a "{" in a comment above it makes Quickshell 0.3.2 build an
// empty object instead of this singleton, silently; TRANSLATION.md.)
//
// The shell's own words in the user's language (tr.mjs is the logic;
// docs/design/TRANSLATION.md the why and the workflow).
//
//   Tr.t("Shut Down")                              Ausschalten
//   Tr.t("Hold to {action}", { action: name })     a sentence with a value in it
//   Tr.n(count, "{n} update", "{n} updates")       the plural form for count
//
// English is the key and the fallback: a language without a catalogue, or a
// key its catalogue lacks, reads English. The language is the first of
// Qt.locale().uiLanguages (LANGUAGE, then LC_MESSAGES/LANG) that has a file
// in shell/i18n/ (listed in i18n/languages.json). KUWAI_PSEUDO=1 swaps every
// string for a longer, accented one, to see what clips.
//
// Only literal strings of the shell go through here. Text from outside it
// (notifications, window titles, track names, file names) is never looked up.
//
// Cost: one small JSON read at start (none for English); a lookup is one
// object key, and a binding that calls t() re-runs only if the catalogue does.

import QtQuick
import Quickshell
import Quickshell.Io
import "tr.mjs" as T

Singleton {
    id: root
    readonly property string dir: Quickshell.shellDir + "/i18n/"
    readonly property var available: T.parse(index.text()).languages || []
    // "de_DE", "de", or "" for English.
    readonly property string language: T.pick(T.candidates(Qt.locale().uiLanguages), available)
    readonly property var catalogue: language ? T.parse(file.text()) : ({})
    readonly property bool pseudo: Quickshell.env("KUWAI_PSEUDO") === "1"
    // Right-to-left languages mirror their layouts (not wired yet: see TRANSLATION.md).
    readonly property bool rtl: Qt.locale().textDirection === Qt.RightToLeft

    function t(text, args) {
        return pseudo ? T.fill(T.pseudo(text), args) : T.t(catalogue, text, args);
    }
    function n(count, one, other, args) {
        if (pseudo) return T.pseudo(T.n({}, "", count, one, other, args));
        return T.n(catalogue, language, count, one, other, args);
    }

    FileView { id: index; path: root.dir + "languages.json"; blockLoading: true; printErrors: false }
    FileView { id: file; path: root.language ? root.dir + root.language + ".json" : ""; blockLoading: true; printErrors: false }
}
