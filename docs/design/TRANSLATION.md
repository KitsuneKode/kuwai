# Translating the shell

Status (2026-11-18): one path proven end to end for two places (the relative
days in `config/Dates.qml`, the power panel), German shipped for them, English
unchanged. Everything else is still hand-written English. This page is the
evidence, the path, the workflow for contributors, and the plan for the rest.

## 1. Qt's own mechanism (`qsTr` + `.qm`) does not work in Quickshell 0.3.2

`qsTr()` only translates when a `QTranslator` is installed on the application.
Quickshell installs none, and nothing in QML can install one.

**Static evidence.** The binary builds a plain `QQmlEngine` (not
`QQmlApplicationEngine`, which is what loads `i18n/qml_<lang>.qm` by itself),
and it never references a translator:

```
$ nm -D --undefined-only /usr/bin/quickshell | c++filt | grep -iE "QQmlApplicationEngine|installTranslator|QTranslator|QQmlEngine::QQmlEngine|uiLanguage"
                 U QQmlEngine::QQmlEngine(QObject*)@Qt_6
```

`/usr/lib/qt6/qml/Quickshell/**.qmltypes` has no type or method about
translation, and `qs --help` has no option for it. `lupdate`/`lrelease` are not
installed here (`qt6-tools` is absent; `/usr/lib/qt6/bin` has neither), so the
test uses a real compiled catalogue Qt already ships: `qtbase_de.qm`, whose
context `QFileDialog` translates `&Open` → `&Öffnen`. Naming the QML file
`QFileDialog.qml` makes a literal `qsTr("&Open")` in it use that context.

**Runtime evidence.** The same probe, the same `.qm` (copied to
`i18n/qml_de.qm` and `i18n/qml_de_DE.qm` beside the entry file), offscreen:

```
# Quickshell 0.3.2, LANG=de_DE.UTF-8 LANGUAGE=de
$ env -i … LANG=de_DE.UTF-8 LANGUAGE=de QT_QPA_PLATFORM=offscreen dbus-run-session -- qs -p shell/shell.qml
  WARN qml: PROBE uiLanguage="" locale=de_DE
  WARN qml: PROBE qsTr(&Open)=&Open qsTr(Hello)=Hello
  WARN qml: PROBE qsTranslate=&Open
  WARN qml: PROBE after uiLanguage=de: &Open
  WARN: Signal QQmlEngine::quit() emitted, but no receivers connected to handle it.

# Control: Qt's own runner (QQmlApplicationEngine), same files
$ env -i … LANG=de_DE.UTF-8 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 /usr/lib/qt6/bin/qml main.qml
qml: PROBE uiLanguage="de" locale=de_DE
qml: PROBE qsTr(&Open)=&Öffnen qsTr(Hello)=Hello
qml: PROBE qsTranslate=&Öffnen
$ env -i … LANG=en_US.UTF-8 … /usr/lib/qt6/bin/qml main.qml
qml: PROBE qsTr(&Open)=&Open …
```

The catalogue and the string are valid: Qt's runner translates them. Under
Quickshell the locale is German (`Qt.locale().name` is `de_DE`), but
`Qt.uiLanguage` is empty, `qsTr`/`qsTranslate` return the English source, and
setting `Qt.uiLanguage = "de"` changes nothing, because nothing loads a
catalogue for it. Making `qsTr` work would need C++: a Quickshell plugin or an
upstream change that installs a `QTranslator`. Quickshell's online
documentation was not consulted from here (no web access in this run); the
conclusion rests on the binary and the run above.

Two more facts from the same probes shaped the alternative:

- `typeof Intl` is `undefined` in Quickshell's JS engine, so there is no
  `Intl.PluralRules`. Plural rules must be our own.
- `Qt.locale().uiLanguages` does follow `LANGUAGE`, then `LC_MESSAGES`/`LANG`:
  `LANGUAGE=de:fr` gives `["de-Latn-DE","de-DE","de-Latn","de","fr-Latn-FR",…]`.
  `Qt.locale().textDirection` is `1` (right to left) under `ar_EG`.

## 2. The path: JSON catalogues and a `Tr` singleton

```
shell/config/tr.mjs      pure logic: lookup, {name} placeholders, CLDR plural rules,
                         language choice, pseudo-locale (bun-tested, tsc-checked)
shell/config/Tr.qml      the singleton: reads the catalogue, exposes t() and n()
shell/i18n/languages.json  {"languages": ["de"]}: the catalogues the shell may load
shell/i18n/de.json       {"Shut Down": "Herunterfahren", …}
bin/kuwai-i18n           keys, coverage, --missing LANG, --check, --count
```

```qml
Label { text: Tr.t("Shut Down") }
Label { text: Tr.t("Connected via {device}", { device: art.via }) }
Label { text: Tr.n(count, "{n} update", "{n} updates") }
```

- **English is the key and the fallback.** No catalogue, a missing key, an empty
  or wrongly shaped value: the English text. A broken JSON file reads as no
  catalogue rather than taking the shell down.
- **Language:** the first entry of `Qt.locale().uiLanguages` (script subtags
  dropped, `de_DE` before `de`) that `languages.json` lists. The list stops
  at English, so `LANGUAGE=en:de` reads English. Dates already follow the same
  locale.
- **Plurals:** a catalogue entry for the English singular gives every CLDR
  category its language uses (`de`: one, other; `ru`: one, few, many, other;
  `ar`: zero … other; `ja`: other, or a plain string). The rules are in
  `tr.mjs` for integers (counts are integers in this UI).
- **Placeholders** `{name}` are filled with plain text and never looked up, so
  a notification's text, a window title or a device name passes through
  untranslated. Labels stay plain-text (`Label`), so translated strings cannot
  inject markup.
- **Pseudo-locale:** `KUWAI_PSEUDO=1` turns every string into `[Šhüt Döwñ ~~~~]`:
  accented, about 40 % longer, bracketed so a clipped end shows.
- **Cost:** one small blocking JSON read at start (none for English). A lookup
  is a function call and one object key. A binding that calls `Tr.t` depends
  only on `Tr.catalogue`, which changes only at start, so nothing re-evaluates
  at rest.

### Why not `qsTr` (once Quickshell supports it)?

| | Qt `.ts`/`.qm` | JSON + `Tr` (chosen) |
| --- | --- | --- |
| Works in Quickshell 0.3.2 | **No** (above) | Yes (tested in a real offscreen Quickshell) |
| Tooling | `lupdate`/`lrelease` (qt6-tools, not installed here); Qt Linguist; Weblate/Transifex read `.ts` | `bin/kuwai-i18n` (extract, coverage, `--missing`, `--check`); Weblate and others read flat JSON (key = source) |
| Build step | `.ts` → `.qm` compile, binary in the tree or built at install | none; the file the translator edits is the file the shell reads |
| Plurals | `%n` with the language's forms, rules built into Qt | CLDR categories by name; rules in `tr.mjs` (integers; 6 families covering the major languages; add a family when a language needs it) |
| Context (same English, two meanings) | built in (file context, disambiguation) | not yet; add `Tr.t("Restart", args, "power")` → key `power\u0004Restart` when the first clash appears |
| Right to left | Qt's `LayoutMirroring`, unrelated to the catalogue | same: `Tr.rtl` is exposed; mirroring is layout work (below) |
| Cost per lookup | C++ hash lookup | one JS call and an object key; bindings re-run only when the catalogue changes |
| Adding a language | run lupdate, translate in Linguist, lrelease, ship `.qm` | `bin/kuwai-i18n --missing fr > shell/i18n/fr.json`, translate, add `"fr"` to `languages.json`, `bin/kuwai-i18n --check` |
| Strings from outside the shell | not translated unless passed to `qsTr` | same; placeholders never looked up |

If Quickshell later installs a translator, the move is mechanical: every key is
a literal in `Tr.t(...)`, which a script can rewrite to `qsTr(...)` and export to `.ts`.

## 3. A trap found on the way: `{` above `pragma Singleton`

Quickshell 0.3.2 treats a `{` before `pragma Singleton`, even inside a
comment, as the start of the object. The file then loads as an empty object
with no error: `Tr.t` was "not a function" while the same file without its
header worked. `Tr.qml` puts the pragma on line 1, and
`tests/shell/test_tr_quickshell.py::test_no_brace_above_pragma_singleton`
checks every singleton under `shell/` for the trap.

## 4. Longer strings: what each surface does at +40 %

German runs about 30 % longer than English, Finnish and Russian more, and short
labels grow more than long ones. The table reads the layout code for ten
representative strings. The two power-panel rows are measured: the real
`PowerPanel` rendered offscreen at `size: 12` (German, and the pseudo-locale at
+40 %).

| # | String (where) | Kind | Layout | At +40 % |
| --- | --- | --- | --- | --- |
| 1 | "Shut Down", "Firmware" (power tiles, `PowerPanel.qml`) | short button | label centred in a fixed 88 px tile, no width, no elide | **Overlaps.** German "Herunterfahren" measures 87 of 88 px; pseudo "Šhüt Döwñ" 104 px and "Fîrmwàré" 95 px run into the neighbouring tile (seen in the render). Fix: `width: tile.width - 12; elide; Tip`, or tiles sized to the longest label |
| 2 | "Hold to restart into the firmware setup" (power hint) | sentence | centred, no width cap, panel 620 px | Fits: German 341 px, pseudo 335 px. It would clip only past ~570 px |
| 3 | "Save" / "Don't save" (`components/ai/ApprovalCard.qml`) | short buttons | `RaisedButton` grows (min 88), right-anchored row | Grows left into the card's text; no clipping, but nothing reserves the width. The concatenation `"Don't " + verb.toLowerCase()` is wrong in German (lower-cases nouns, wrong order): it needs whole strings |
| 4 | "Pull down or tap to read · swipe up to dismiss" (`NotifPeek.qml`, 10 px) | hint line | `width: parent.width` (~370 px of a fixed 460 px peek), no wrap, no elide | About 245 px now, about 345 px at +40 %: at the edge. German is about 370 px and draws past the column. Needs elide or a wrap |
| 5 | "A glance (app, time, music); click it for everything. Super+Alt+I opens everything too" (Settings, `SettingsRow` detail) | long description | `wrapMode: Text.Wrap`; row height follows | Copes: wraps to another line. The label beside it elides, with no Tip |
| 6 | "The battery is below 30%. An update that's cut off by a dead battery can leave the system unbootable." (`UpdatesPanel` → `ui/Notice`) | sentence with a number | wrap, `maximumLineCount: 2`, then elide | About 145 characters at 11 px in a ~700 px column is about 2 lines: just fits; past that the end is cut with no way to read it. Notice needs 3 lines or a Tip |
| 7 | "tokens: every skill was used in the last {n} days. Nothing to clear." (`CleanupPanel.qml`) | number + plural | wraps, full width | Layout copes; the code concatenates 3 pieces around the number, so it needs `Tr.n` |
| 8 | "Connected via {device}" (OSD subtitle, `osd/Osd.qml`) | one variable | `elide: ElideRight` in a fixed 316 px HUD | Elided, no Tip; long device names already hit this |
| 9 | "A password is needed · click to bring it here" (`IslandRest` activity Tip) | hint | `Tip`: single line, unbounded width | Grows (about 380 px); fine on a laptop screen, no wrap if a language runs very long |
| 10 | "Couldn't end {name}: {why}" (`LauncherPanel.qml` result sub-line) | two variables | `elide: ElideRight`, full row width, no Tip | The reason (the useful part) is the first thing cut. Put the reason on its own line, or add a Tip |

Patterns: fixed-width tiles with unbounded labels (power tiles, quick-settings
tiles: `ui/Tile`, `ui/ControlTile` are the next to check) overlap; single-line
elides without a `Tip` lose the meaning; wrapped details cope. The pseudo-locale
plus `tests/ui/tr-probe.qml` is the tool: render a surface under
`KUWAI_PSEUDO=1` and measure each label against its box.

Right to left (Arabic, Hebrew) is separate work: `LayoutMirroring.enabled` on
each window root, then a pass over every hand-placed `x:` and every
`anchors.left` that means "start". The island's left/right halves are
positional, not reading order, and need a decision.

## 5. Contributor workflow

Adding a string:

```qml
Label { text: Tr.t("Battery saver") }                         // a whole sentence or label
Label { text: Tr.t("Connected via {device}", { device: d }) }  // values as {placeholders}
Label { text: Tr.n(n, "{n} update", "{n} updates") }           // counts: both English forms
```

- Never build a sentence from pieces (`"Moved " + n + " files"`, or
  `label.toLowerCase()`): word order and case differ by language. One key per
  sentence.
- Never pass outside text to `Tr.t` (`Tr.t(notif.summary)`): it would be looked
  up, and it isn't ours. Put it in a placeholder.
- A key must be a literal (`Tr.t("…")`, not `Tr.t(variable)`), or the extractor
  can't see it. A table of labels (like the power actions) calls `Tr.t` per entry.

Adding a language:

```sh
bin/kuwai-i18n --missing fr > shell/i18n/fr.json   # every key, empty values (plural keys as {one, other})
# translate; add the categories your language uses (ru: one few many other); delete what you skip
# add "fr" to shell/i18n/languages.json
bin/kuwai-i18n --check && bun test tests/shell/tr.test.mjs
LANGUAGE=fr qs -p shell   # (in a worktree's own instance, never the live session)
```

An empty value reads English, so a partial catalogue is safe. If the language
has a plural rule `tr.mjs` doesn't know yet, add its family there with a test.

## 6. Plan for the rest of the shell

Sized with `bin/kuwai-i18n --count` (a heuristic: by sampling, about 85 % of
what it counts is real UI text). It finds about **2,530 literal sites, about
1,880 unique strings**, of which about **400 are fragments** (a leading or
trailing space or punctuation: pieces of concatenated sentences, which must be
rewritten, not wrapped), median length 12 characters, 86 longer than 60.

| Order | Area | Literal sites | Notes |
| --- | --- | --- | --- |
| 1 | `components/` (incl. `ui/`, `ai/`) | 166 | shared primitives first: everything else inherits their states (empty, error, buttons) |
| 2 | `modules/island` (33 files) | 1,142 | the bulk: panels, rest, hover. Split by panel: Power ✓, System, Bluetooth, Updates, Cleanup, Launcher, Settings (the longest descriptions), Themes, Keys |
| 3 | `modules/notifications`, `osd`, `lock`, `greeter.qml` | 158 + 31 + 47 + 5 | the always-seen surfaces; the greeter runs as another user, with the system locale |
| 4 | `services/` | 544 | status words that reach the UI (`Updates.phaseLabel`, adapters' "Hit a limit"); the rest are logs and commands, not UI: wrap at the boundary where they're shown |
| 5 | `modules/clipboard`, `assistant`, `overview`, rest | 231 + 50 + 9 + … | including the clipboard's own "Today/Yesterday" section names |
| 6 | `config/settings-schema.json` labels and help | (in JSON) | needs an extractor pass for the schema (keys = its English labels) |

At a careful pace (about 150 sites a day, with fragment rewrites), that is
about three weeks for one person, with each area landing on its own commit and
its keys in `de.json`.

**The check that no new hard-coded string is added:** a ratchet like
`bin/kuwai-tokens`. `bin/kuwai-i18n --count` already gives the per-area counts;
add `--check-literals` against a baseline (`docs/design/i18n-baseline.json`)
that may only go down, and call it from `bin/kuwai-check` beside the token
ratchet. It isn't wired in yet on purpose: two other workers are changing the
same QML today, and a baseline taken now would fail their next commit. Turn it
on at the start of step 1, when the baseline can be taken on a quiet tree.
`bin/kuwai-i18n --check` (catalogue integrity: listed, no stale keys,
placeholders kept, plural shape) can go into `kuwai-check` and CI now.

## 7. Tests

- `tests/shell/tr.test.mjs` (bun): English by default; German under a German
  language list; an unknown key, an empty value or a wrong shape falls back to
  English; plural forms (German, Russian 1/2/5/11/21/22/25/112, Polish, French
  0/1, Arabic 0–100, Japanese); placeholders never looked up; the language
  order (`LANGUAGE`, English stops it); a broken catalogue; the pseudo-locale is
  at least 40 % longer; every shipped plural entry has its language's
  categories; Dates' relative days in German.
- `tests/shell/test_tr_quickshell.py` (pytest, real Quickshell, offscreen, bwrap
  like `bin/kuwai-ui-test`): the real `PowerPanel` and `Dates` under `C.UTF-8`
  (English), `de_DE.UTF-8` (German tiles, hint, "Heute"/"Gestern", a plural
  through the singleton, the English fallback, a placeholder not looked up),
  `LANGUAGE=fr:de` (→ German), `LANGUAGE=en:de` (→ English), and
  `KUWAI_PSEUDO=1`; plus the `pragma Singleton` trap over all of `shell/`. It
  saves `power.png` in the test's temp folder. `services/` is reduced to the
  two calls PowerPanel makes, because the real services need a layer-shell
  window that offscreen doesn't have.

## Not verified

- On the live session (the brief forbids touching it): the panel in German on
  a real screen, at the owner's text scale.
- Quickshell's online documentation and newer releases (no web access in this run).
- The German wording has not been reviewed by a native speaker
  ("Bereitschaft" vs "Standby", "Herunterfahren" vs GNOME's "Ausschalten").
- `bin/kuwai-i18n --count` is a heuristic; the sizes are estimates.
