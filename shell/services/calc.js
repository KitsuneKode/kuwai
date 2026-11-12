.pragma library
// The launcher's calculator (modules/island/LauncherPanel), as one function
// with no Qt in it, so it can be tested (tests/shell/calc.test.mjs):
//
//   evaluate(text, fx) → { value, expr, note, pending } or null
//
//   12 * 7 · 12 x 7 · (3 + 4)^2                 arithmetic
//   100 + 10%  → 110 · 250 - 20% → 200          a percent of what's before it
//   15% of 80  → 12                             (as a calculator does)
//   10 km to miles · 72 f in c · 3 gib to mb    one unit to another
//   6 mi + 376 yd + 4.78 in [to m]              mixed units, summed
//   20 usd to yen · $20 in rupees · 5€ to £     currencies, by code, name or sign
//
// fx: { time, rates: { USD: 1, INR: 83.1, … } } (rates per US dollar) or null.
// Anything it can't read returns null; the launcher may ask qalc then.

var UNITS = {
    // length (m)
    mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], meter: ["len", 1], meters: ["len", 1], metre: ["len", 1], metres: ["len", 1],
    km: ["len", 1000], kilometer: ["len", 1000], kilometers: ["len", 1000], kilometre: ["len", 1000], kilometres: ["len", 1000],
    in: ["len", 0.0254], inch: ["len", 0.0254], inches: ["len", 0.0254], ft: ["len", 0.3048], foot: ["len", 0.3048], feet: ["len", 0.3048],
    yd: ["len", 0.9144], yard: ["len", 0.9144], yards: ["len", 0.9144], mi: ["len", 1609.344], mile: ["len", 1609.344], miles: ["len", 1609.344],
    nmi: ["len", 1852],
    // mass (g)
    mg: ["mass", 0.001], g: ["mass", 1], gram: ["mass", 1], grams: ["mass", 1], kg: ["mass", 1000], kilo: ["mass", 1000], kilos: ["mass", 1000],
    lb: ["mass", 453.59237], lbs: ["mass", 453.59237], pound: ["mass", 453.59237], oz: ["mass", 28.349523125], ounce: ["mass", 28.349523125],
    ounces: ["mass", 28.349523125], st: ["mass", 6350.29318], stone: ["mass", 6350.29318], t: ["mass", 1e6], tonne: ["mass", 1e6],
    // data (bytes)
    b: ["data", 1], byte: ["data", 1], bytes: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12],
    kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
    // time (s)
    ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], secs: ["time", 1], second: ["time", 1], seconds: ["time", 1],
    min: ["time", 60], mins: ["time", 60], minute: ["time", 60], minutes: ["time", 60], h: ["time", 3600], hr: ["time", 3600],
    hrs: ["time", 3600], hour: ["time", 3600], hours: ["time", 3600], d: ["time", 86400], day: ["time", 86400], days: ["time", 86400],
    wk: ["time", 604800], week: ["time", 604800], weeks: ["time", 604800],
    // volume (l)
    ml: ["vol", 0.001], l: ["vol", 1], liter: ["vol", 1], liters: ["vol", 1], litre: ["vol", 1], litres: ["vol", 1],
    gal: ["vol", 3.785411784], gallon: ["vol", 3.785411784], gallons: ["vol", 3.785411784], cup: ["vol", 0.2365882365],
    cups: ["vol", 0.2365882365], floz: ["vol", 0.0295735295625], tbsp: ["vol", 0.01478676478125], tsp: ["vol", 0.00492892159375],
    // speed (m/s)
    kmh: ["speed", 1 / 3.6], kph: ["speed", 1 / 3.6], mph: ["speed", 0.44704], mps: ["speed", 1], knot: ["speed", 0.514444],
    knots: ["speed", 0.514444],
    // area (m²)
    sqm: ["area", 1], m2: ["area", 1], sqft: ["area", 0.09290304], ft2: ["area", 0.09290304], acre: ["area", 4046.8564224],
    acres: ["area", 4046.8564224], ha: ["area", 10000], hectare: ["area", 10000], hectares: ["area", 10000], sqkm: ["area", 1e6], km2: ["area", 1e6]
};

// Currency names and signs → ISO codes (any three letters is a code too).
var CURRENCIES = {
    "$": "USD", dollar: "USD", dollars: "USD", buck: "USD", bucks: "USD", "€": "EUR", euro: "EUR", euros: "EUR",
    "₹": "INR", rupee: "INR", rupees: "INR", rs: "INR", "£": "GBP", pound: "GBP", pounds: "GBP", quid: "GBP", sterling: "GBP",
    "¥": "JPY", yen: "JPY", yuan: "CNY", rmb: "CNY", renminbi: "CNY", "₩": "KRW", won: "KRW", franc: "CHF", francs: "CHF",
    "₽": "RUB", ruble: "RUB", rubles: "RUB", rouble: "RUB", roubles: "RUB", dirham: "AED", dirhams: "AED", riyal: "SAR",
    riyals: "SAR", baht: "THB", taka: "BDT", ringgit: "MYR", rupiah: "IDR", lira: "TRY", "₺": "TRY", zloty: "PLN", krona: "SEK",
    kronor: "SEK", krone: "NOK", rand: "ZAR", dong: "VND", "₫": "VND", peso: "MXN", pesos: "MXN", real: "BRL", reais: "BRL",
    "₱": "PHP", nzd: "NZD", aud: "AUD", cad: "CAD", sgd: "SGD", hkd: "HKD"
};

function fmt(x) {
    if (!isFinite(x)) return "";
    var a = Math.abs(x);
    var r = a >= 100 ? Math.round(x * 100) / 100 : a >= 1 ? Math.round(x * 1e4) / 1e4 : Math.round(x * 1e8) / 1e8;
    var s = String(r);
    if (/e/.test(s)) return s;
    var parts = s.split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parts.join(".");
}

// Plain arithmetic: digits, + - * / % ^ ( ) . and × ÷ x between numbers.
function arith(q, bare) {
    var s = q.replace(/×/g, "*").replace(/÷/g, "/").replace(/(\d)\s*x\s*(?=[\d(])/gi, "$1*").replace(/,(?=\d{3}\b)/g, "");
    if (!/^[\d\s+\-*/().%^]+$/.test(s) || !/\d/.test(s)) return null;
    // "a + b%" / "a - b%": a percent of what's before it, as a calculator does.
    var tail = /^(.+?)\s*([+\-])\s*(\d+(?:\.\d+)?)\s*%\s*$/.exec(s);
    if (tail) {
        var left = arith(tail[1], true);
        if (left === null) return null;
        var p = Number(tail[3]) / 100;
        return tail[2] === "+" ? left * (1 + p) : left * (1 - p);
    }
    if (!/[+\-*/%^]/.test(s) && !bare) return null;
    s = s.replace(/(\d+(?:\.\d+)?)\s*%/g, "($1/100)").replace(/\^/g, "**");
    try {
        var v = Function('"use strict"; return (' + s + ");")();
        return typeof v === "number" && isFinite(v) ? Math.round(v * 1e10) / 1e10 : null;
    } catch (e) {
        return null;
    }
}

function unitOf(word) {
    var w = String(word || "").toLowerCase().replace(/[°.]/g, "");
    return UNITS[w] ? { key: w, dim: UNITS[w][0], f: UNITS[w][1] } : null;
}
function currencyOf(word) {
    var w = String(word || "").toLowerCase();
    if (CURRENCIES[w]) return CURRENCIES[w];
    return /^[a-z]{3}$/.test(w) ? w.toUpperCase() : "";
}

function evaluate(text, fx) {
    var q = String(text || "").trim().replace(/^=\s*/, "");
    if (!q) return null;
    var n;

    // 15% of 80
    var pct = /^(-?\d+(?:\.\d+)?)\s*%\s*of\s*(-?[\d.,]+)$/i.exec(q);
    if (pct) {
        n = Number(pct[1]) / 100 * Number(pct[2].replace(/,/g, ""));
        return { value: fmt(n), expr: pct[1] + "% of " + pct[2] };
    }

    var a = arith(q);
    if (a !== null) return { value: fmt(a), expr: q.replace(/\*/g, "×").replace(/\s+/g, " ") };

    // Temperature isn't a ratio.
    var t = /^(-?[\d.,]+)\s*°?\s*([cfk])\s*(?:to|in|->|=|as)\s*°?\s*([cfk])$/i.exec(q);
    if (t) {
        var v0 = Number(t[1].replace(/,/g, "")), f = t[2].toLowerCase(), to = t[3].toLowerCase();
        var c = f === "c" ? v0 : f === "f" ? (v0 - 32) * 5 / 9 : v0 - 273.15;
        var out = to === "c" ? c : to === "f" ? c * 9 / 5 + 32 : c + 273.15;
        return { value: fmt(out) + " °" + to.toUpperCase(), expr: t[1] + " °" + f.toUpperCase() };
    }

    // Currencies: "20 usd to yen", "$20 in rupees", "5€ to £".
    var cm = /^([$€₹£¥₩₽₺₫₱]?)\s*(-?[\d.,]+)\s*([a-z$€₹£¥₩₽₺₫₱]*)\s*(?:to|in|->|=|as)\s*([a-z$€₹£¥₩₽₺₫₱]+)$/i.exec(q);
    if (cm && !(unitOf(cm[3]) && unitOf(cm[4]))) {
        var from = currencyOf(cm[1] || cm[3]), dest = currencyOf(cm[4]);
        if (from && dest && !unitOf(cm[3])) {
            var amount = Number(cm[2].replace(/,/g, ""));
            if (!fx || !fx.rates) return { value: "…", expr: fmt(amount) + " " + from, note: "Fetching today's rates", pending: true };
            var ra = fx.rates[from], rb = fx.rates[dest];
            if (ra && rb) return { value: fmt(amount / ra * rb) + " " + dest, expr: fmt(amount) + " " + from, note: "rates of the day", rates: true };
        }
    }

    // Units, one or several summed: "10 km to miles", "6 mi + 376 yd + 4.78 in to m".
    var um = /^(.+?)(?:\s+(?:to|in|->|as)\s+([a-z°]+))?$/i.exec(q);
    if (um) {
        var terms = [], re = /([+\-]?)\s*(\d+(?:\.\d+)?)\s*([a-z°]+)\s*/gi, m2, used = 0;
        while ((m2 = re.exec(um[1])) !== null) {
            var u = unitOf(m2[3]);
            if (!u) return null;
            terms.push({ sign: m2[1] === "-" ? -1 : 1, v: Number(m2[2]), u: u, text: (m2[1] && terms.length ? m2[1] + " " : "") + m2[2] + " " + m2[3] });
            used += m2[0].length;
        }
        if (terms.length && used === um[1].length) {
            var dim = terms[0].u.dim;
            for (var i = 0; i < terms.length; i++) if (terms[i].u.dim !== dim) return null;
            var target = um[2] ? unitOf(um[2]) : terms[0].u;
            if (!target || target.dim !== dim || (terms.length === 1 && !um[2])) return null;
            var base = 0;
            for (var j = 0; j < terms.length; j++) base += terms[j].sign * terms[j].v * terms[j].u.f;
            return { value: fmt(base / target.f) + " " + (um[2] || terms[0].u.key), expr: terms.map(function (x) { return x.text; }).join(" ") };
        }
    }
    return null;
}

// Worth asking qalc about when evaluate() couldn't: digits with an operator,
// a unit-ish word or "to". (Never plain words: "firefox" isn't math.)
function looksLikeMath(text) {
    var q = String(text || "").trim().replace(/^=\s*/, "");
    return /\d/.test(q) && (/[+\-*/^%×÷()]/.test(q) || /\b(to|in|of|as)\b/i.test(q) || /\d\s*[a-z]{1,10}\b/i.test(q)) && q.length < 120;
}
