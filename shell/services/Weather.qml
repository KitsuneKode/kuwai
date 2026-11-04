pragma Singleton

// Current weather for the island: wttr.in's JSON (no key), every 30 minutes,
// for Settings.weatherLocation (default: the city HyDE's config.toml names).
// Offline or failing: `ok` stays false and nothing is shown. One curl per
// half hour, bounded to 8 s.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root
    property bool ok: false
    property int temp: 0
    property int feels: 0
    property int humidity: 0
    property int wind: 0
    property string desc: ""
    property string glyph: "\u{f0599}"
    readonly property string location: Settings.weatherLocation || "North Lakhimpur"

    // wttr/WWO weather codes → Material Design glyphs (Symbols Nerd Font).
    function glyphFor(code, night) {
        const c = Number(code);
        if (c === 113) return night ? "\u{f0594}" : "\u{f0599}";            // clear
        if (c === 116) return night ? "\u{f0f31}" : "\u{f0595}";            // partly cloudy
        if (c === 119 || c === 122) return "\u{f0590}";                       // cloudy
        if ([143, 248, 260].includes(c)) return "\u{f0591}";                  // fog
        if ([200, 386, 389, 392, 395].includes(c)) return "\u{f0593}";        // thunder
        if ([179, 182, 185, 227, 230, 311, 314, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377].includes(c)) return "\u{f0598}"; // snow / sleet
        return "\u{f0597}";                                                   // rain
    }

    Process {
        id: fetch
        command: ["curl", "-sf", "--max-time", "8", "https://wttr.in/" + encodeURIComponent(root.location) + "?format=j1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const c = d.current_condition[0];
                    const h = new Date().getHours();
                    root.temp = Number(c.temp_C);
                    root.feels = Number(c.FeelsLikeC);
                    root.humidity = Number(c.humidity);
                    root.wind = Number(c.windspeedKmph);
                    root.desc = (c.weatherDesc && c.weatherDesc[0] ? c.weatherDesc[0].value : "").trim();
                    root.glyph = root.glyphFor(c.weatherCode, h < 6 || h >= 18);
                    root.ok = true;
                    retry.stop();
                } catch (e) { retry.start(); /* keep the last good reading; try again soon */ }
            }
        }
        // No answer (offline, wttr.in busy): try again in 2 minutes, not 30.
        onExited: code => { if (code !== 0) retry.start(); }
    }
    Timer { id: retry; interval: 2 * 60 * 1000; onTriggered: fetch.running = true }
    Timer { interval: 30 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: fetch.running = true }
}
