import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services
import "../../services/spendreport.mjs" as SR

Column {
    id: sv
    property string metric: "cost"
    property string period: "7d"
    property real maxH: 400
    property var doc: null
    property var cache: ({})
    property bool failed: false
    readonly property bool tokens: metric === "tokens"
    readonly property var rep: doc ? SR.report(doc.buckets || [], doc.sessions || {}, doc.period, metric, Date.now()) : null
    readonly property bool fromT3: !!doc && (doc.source === "t3" || doc.source === "t3-db")
    readonly property string coverage: doc ? SR.coverageText(doc.coverage) : ""
    function instancesOf(id) {
        const list = doc && doc.instances ? doc.instances[id] || [] : [];
        return list.length > 1 || (list.length === 1 && Providers.name(list[0]) !== SR.providerName(id)) ? list.map(i => Providers.name(i)).join(" · ") : "";
    }
    readonly property var periods: [{ id: "24h", label: "24h" }, { id: "7d", label: "7d" }, { id: "30d", label: "30d" }, { id: "90d", label: "90d" }]
    spacing: Theme.s3

    function value(x) { return SR.valueText(x, tokens); }
    function shareText(x) { return !tokens && !(x.cost > 0) ? "" : "  " + Math.round(x.share * 100) + "%"; }
    function tone(id) {
        return ({ claude: Theme.orange, codex: Theme.green, grok: Theme.textSecondary, cursor: Theme.cyan, opencode: Theme.indigo,
                  antigravity: Theme.blue, gemini: Theme.blue, pi: Theme.mint, muse: Theme.pink })[id] || Theme.brown;
    }
    function step(d) {
        const i = periods.findIndex(p => p.id === period);
        period = periods[(i + d + periods.length) % periods.length].id;
    }
    function load() {
        if (cache[period]) doc = cache[period];
        if (proc.running) return;
        proc.want = period;
        proc.running = true;
    }
    onPeriodChanged: load()
    onVisibleChanged: if (visible) load()
    Component.onCompleted: if (visible) load()

    Process {
        id: proc
        property string want: "7d"
        command: ["setpriv", "--pdeathsig", "KILL", "--", "sh", "-c",
                  'command -v bun >/dev/null 2>&1 && exec bun "$1" "$2"; exec node "$1" "$2"', "kuwai-spend-report", Paths.bin + "/kuwai-spend-report", want]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const c = Object.assign({}, sv.cache);
                    c[d.period] = d;
                    sv.cache = c;
                    if (d.period === sv.period) sv.doc = d;
                    sv.failed = false;
                } catch (e) { sv.failed = !sv.doc; }
                if (proc.want !== sv.period) Qt.callLater(sv.load);
            }
        }
    }

    Segmented {
        width: sv.width
        options: sv.periods
        current: sv.period
        onPicked: id => sv.period = id
    }

    Column {
        visible: !sv.doc && !sv.failed
        width: sv.width
        spacing: Theme.s2
        Skeleton { width: parent.width * 0.4; height: Theme.sp(30); radius: Theme.r1 }
        Skeleton { width: parent.width; height: Theme.sp(96); radius: Theme.r2 }
    }

    Ui.Notice {
        visible: sv.failed
        width: sv.width
        glyph: "\u{f0026}"
        title: "Usage can't be read right now"
        action: "Retry"
        onActed: sv.load()
    }
    Ui.EmptyState {
        visible: !sv.failed && !!sv.rep && sv.rep.empty
        width: sv.width
        topPadding: Theme.s3; bottomPadding: Theme.s3
        glyph: "\u{f0128}"
        title: "No usage in this period"
        body: "Pick a longer period above."
    }

    Item {
      visible: !!sv.rep && !sv.rep.empty
      width: sv.width
      height: flick.height
    Flickable {
        id: flick
        width: parent.width
        height: Math.min(body.implicitHeight, sv.maxH)
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: body
            width: flick.width
            spacing: Theme.s4

            Column {
                width: parent.width
                spacing: Theme.s1
                Label {
                    text: !sv.rep ? "" : sv.tokens ? SR.compact(sv.rep.totals.tokens) : SR.money(sv.rep.totals.cost)
                    size: Theme.tTitle1; weight: Theme.wBold; rounded: true
                    tabular: true
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: !sv.rep ? "" : [
                        sv.tokens ? "processed tokens" : "API estimate",
                        sv.rep.sessions ? sv.rep.sessions + (sv.rep.sessions === 1 ? " session" : " sessions") : "",
                        !sv.tokens && sv.rep.totals.saved > 0 ? SR.money(sv.rep.totals.saved) + " saved by cache" : "",
                        sv.tokens && sv.rep.hitRate > 0 ? "cache hit " + Math.round(sv.rep.hitRate * 100) + "%" : "",
                        sv.rep.totals.unpriced > 0 ? SR.compact(sv.rep.totals.unpriced) + " tokens without a price" : ""
                    ].filter(x => x).join(" · ")
                    size: Theme.tFootnote; color: Theme.textTertiary
                    tabular: true
                }
                Label {
                    visible: sv.coverage !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: sv.coverage
                    size: Theme.tFootnote; color: Theme.textTertiary
                    tabular: true
                }
            }

            Item {
                id: chart
                width: parent.width
                height: Theme.sp(96)
                property int hot: -1
                readonly property var slots: sv.rep ? sv.rep.chart : []
                readonly property real slotW: slots.length ? width / slots.length : 0
                Canvas {
                    id: bars
                    anchors.fill: parent
                    property var rep: sv.rep
                    property int hot: chart.hot
                    onRepChanged: requestPaint()
                    onHotChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        if (!rep || rep.peak <= 0) return;
                        const n = rep.chart.length, w = width / n, gap = Math.min(Theme.s1 / 2, w * 0.25);
                        const order = rep.providers.map(p => p.id);
                        for (let i = 0; i < n; i++) {
                            const s = rep.chart[i];
                            let y = height;
                            for (const id of order) {
                                const v = s.parts[id] || 0;
                                if (v <= 0) continue;
                                const h = Math.max(1, v / rep.peak * (height - Theme.s1));
                                c.fillStyle = Qt.alpha(sv.tone(id), hot < 0 || hot === i ? 0.9 : 0.4);
                                c.fillRect(i * w + gap / 2, y - h, Math.max(1, w - gap), h);
                                y -= h;
                            }
                        }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.cardEdge }
                MouseArea {
                    id: chartArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: m => chart.hot = chart.slotW > 0 ? Math.max(0, Math.min(chart.slots.length - 1, Math.floor(m.x / chart.slotW))) : -1
                    onExited: chart.hot = -1
                }
                Item {
                    x: chart.hot >= 0 ? (chart.hot + 0.5) * chart.slotW : 0
                    width: 1; height: parent.height
                    Tip {
                        shown: chart.hot >= 0
                        below: true
                        text: {
                            const s = chart.slots[chart.hot];
                            if (!s) return "";
                            const head = sv.period === "24h" ? s.label + ":00" : s.key;
                            const parts = Object.keys(s.parts).filter(k => s.parts[k] > 0)
                                .map(k => SR.providerName(k) + " " + (sv.tokens ? SR.compact(s.parts[k]) : SR.money(s.parts[k])));
                            return head + " · " + (sv.tokens ? SR.compact(s.total) : SR.money(s.total)) + (parts.length > 1 ? "\n" + parts.join(" · ") : "");
                        }
                    }
                }
                Accessible.role: Accessible.Chart
                Accessible.name: (sv.tokens ? "Tokens" : "Spend") + " by " + (sv.period === "24h" ? "hour" : "day")
            }
            Row {
                width: parent.width
                Label {
                    width: parent.width / 2
                    text: chart.slots.length ? (sv.period === "24h" ? chart.slots[0].label + ":00" : chart.slots[0].key.slice(5)) : ""
                    size: Theme.tCaption; color: Theme.textTertiary
                }
                Label {
                    width: parent.width / 2
                    horizontalAlignment: Text.AlignRight
                    text: sv.period === "24h" ? "now" : "today"
                    size: Theme.tCaption; color: Theme.textTertiary
                }
            }

            Column {
                width: parent.width
                spacing: Theme.s2
                Label { text: "By provider"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textSecondary }
                Repeater {
                    model: sv.rep ? sv.rep.providers : []
                    delegate: Column {
                        id: prow
                        required property var modelData
                        width: parent.width
                        spacing: Theme.s1
                        Item {
                            width: parent.width
                            height: Math.max(Theme.sp(20), pname.implicitHeight)
                            AgentMark {
                                id: plogo
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.sp(16); height: width
                                tiled: false
                                agent: prow.modelData.id
                                name: SR.providerName(prow.modelData.id)
                                tint: sv.tone(prow.modelData.id)
                            }
                            Label {
                                id: pname
                                x: Theme.sp(16) + Theme.s2
                                anchors.verticalCenter: parent.verticalCenter
                                text: SR.providerName(prow.modelData.id) + (prow.modelData.sessions ? "  " : "")
                                size: Theme.tBody; weight: Theme.wMedium
                            }
                            Label {
                                anchors { left: pname.right; verticalCenter: parent.verticalCenter }
                                visible: prow.modelData.sessions > 0
                                text: prow.modelData.sessions + (prow.modelData.sessions === 1 ? " session" : " sessions")
                                size: Theme.tFootnote; color: Theme.textTertiary
                            }
                            Label {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: sv.value(prow.modelData) + sv.shareText(prow.modelData)
                                size: Theme.tBody; weight: Theme.wSemibold
                                color: !sv.tokens && !(prow.modelData.cost > 0) ? Theme.textTertiary : Theme.textPrimary
                                tabular: true
                            }
                        }
                        Label {
                            visible: text !== ""
                            x: Theme.sp(16) + Theme.s2
                            width: parent.width - x
                            elide: Text.ElideRight
                            text: sv.instancesOf(prow.modelData.id)
                            size: Theme.tFootnote; color: Theme.textTertiary
                        }
                        Rectangle {
                            width: parent.width; height: Theme.s1; radius: height / 2
                            color: Theme.pill
                            Rectangle {
                                width: Math.max(height, parent.width * prow.modelData.share); height: parent.height; radius: parent.radius
                                color: sv.tone(prow.modelData.id)
                            }
                        }
                        Accessible.role: Accessible.StaticText
                        Accessible.name: SR.providerName(prow.modelData.id) + ", " + sv.value(prow.modelData) + (sv.shareText(prow.modelData) ? ", " + Math.round(prow.modelData.share * 100) + " percent" : "")
                    }
                }
            }

            Column {
                visible: sv.tokens && sv.fromT3 && !!sv.rep && sv.rep.totals.tokens > 0
                width: parent.width
                spacing: Theme.s1
                Label { text: "By type"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textSecondary }
                Repeater {
                    model: !sv.rep ? [] : [["Input", sv.rep.totals.input], ["Cached input", sv.rep.totals.cached], ["Cache writes", sv.rep.totals.cacheWrite], ["Output", sv.rep.totals.output]].concat(sv.rep.totals.other > 0 ? [["Subagents and compaction", sv.rep.totals.other]] : [])
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: tl.implicitHeight
                        Label { id: tl; text: modelData[0]; size: Theme.tSub; color: Theme.textSecondary }
                        Label { anchors.right: parent.right; text: SR.compact(modelData[1]); size: Theme.tSub; tabular: true }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.s1
                Label { text: "Models"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textSecondary }
                Repeater {
                    model: sv.rep ? sv.rep.models.slice(0, 5) : []
                    delegate: Item {
                        id: mrow
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: mname.implicitHeight + Theme.s1
                        Label {
                            id: mname
                            width: parent.width - mval.implicitWidth - Theme.s3
                            elide: Text.ElideRight
                            text: (mrow.index + 1) + "  " + (SR.modelName(mrow.modelData.model) || SR.providerName(mrow.modelData.provider))
                            size: Theme.tSub
                        }
                        Label {
                            id: mval
                            anchors.right: parent.right
                            text: sv.value(mrow.modelData) + sv.shareText(mrow.modelData)
                            size: Theme.tSub; color: Theme.textSecondary
                            tabular: true
                        }
                    }
                }
            }

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                text: sv.doc && sv.doc.source === "t3-db" ? "From T3 Code's own turn records" + (sv.doc.outside > 0 ? ", and this machine's logs for agents run outside T3" : "") + ". Money is an estimate at list prices; a subscription doesn't pay these."
                    : sv.fromT3 ? "From T3 Code's usage records. Money is what the APIs would charge."
                    : "From the logs Claude, Codex and OpenCode keep on this machine. Money is an estimate at list prices."
                      + (sv.doc && sv.doc.why === "scope" ? " T3 Code's fuller records need a token with usage access (README → Usage)." : "")
                size: Theme.tCaption; color: Theme.textTertiary
            }
        }
    }
    ScrollFade { flickable: flick }
    }
}
