export const SWITCH_SETTLE_MS = 600;
export const ZERO_HOLD_MS = 400;
export const FRESH_NODE_MS = 10000;
export const INPUT_SETTLE_SUPPRESS_MS = 2500;
export const MAX_SINK_TRIES = 12;

export function createOsdState() {
    return {
        armed: false,
        sinkSwitchedAt: 0,
        sinkTries: 0,
        lastOut: null,
        leftOut: null,
        firstSeen: {},
        knownIns: [],
        insChangedAt: 0,
        inWas: "",
        soundOutWas: "",
        soundInWas: ""
    };
}

export function volumeDecision(state, volume, now) {
    if (!state.armed || volume < 0 || now - state.sinkSwitchedAt <= SWITCH_SETTLE_MS) return "ignore";
    return volume === 0 ? "holdZero" : "show";
}

export function shouldFireZeroHold(state, volume, now) {
    return !!(state.armed && now - state.sinkSwitchedAt > ZERO_HOLD_MS && volume === 0);
}

export function shouldShowMute(state, now) {
    return !!(state.armed && now - state.sinkSwitchedAt > SWITCH_SETTLE_MS);
}

export function updateFirstSeen(firstSeen, deviceNames, armed, now) {
    const seen = {};
    const prev = firstSeen || {};
    for (let i = 0; i < deviceNames.length; i++) {
        const name = deviceNames[i];
        seen[name] = prev[name] || (armed ? now : 1);
    }
    return seen;
}

export function isFreshNode(firstSeen, name, now, windowMs) {
    const limit = windowMs || FRESH_NODE_MS;
    const t = (firstSeen && firstSeen[name]) || 0;
    return t > 0 && now - t < limit;
}

export function isUnplugged(leftOut, currentOutName, nodeNames) {
    if (!leftOut || !leftOut.wired) return false;
    if (currentOutName && leftOut.name === currentOutName) return false;
    return !(nodeNames || []).includes(leftOut.name);
}

export function resolveOutputSwitch(opts) {
    const notifyGone = opts.bar === "island" && isUnplugged(opts.leftOut, opts.currentOutName, opts.nodeNames);
    const current = opts.currentOut;
    const showConnectedCard = !!(
        opts.bar === "island" &&
        current &&
        current.wired &&
        isFreshNode(opts.firstSeen, opts.currentOutName, opts.now) &&
        !opts.quietSound
    );
    return {
        notifyGone,
        action: showConnectedCard ? "inputCard" : "showVolume"
    };
}

export function diffExternalInputs(knownIns, currentIns, opts) {
    const prev = knownIns || [];
    const curr = currentIns || [];
    const added = curr.filter(x => !prev.some(k => k.name === x.name));
    const gone = prev.filter(k => !curr.some(x => x.name === k.name));
    if (!opts.armed) {
        return {
            knownIns: curr,
            baselineKeys: curr.map(x => x.key),
            pendingCard: null,
            insChangedAt: opts.prevChangedAt || 0
        };
    }
    if (opts.bar !== "island" || (!added.length && !gone.length)) {
        return {
            knownIns: curr,
            baselineKeys: [],
            pendingCard: null,
            insChangedAt: opts.prevChangedAt || 0
        };
    }
    const pick = added.length ? added[added.length - 1] : gone[gone.length - 1];
    return {
        knownIns: curr,
        baselineKeys: [],
        pendingCard: {
            key: pick.key,
            glyph: opts.externalMicGlyph,
            image: pick.image,
            title: pick.title,
            link: "usb",
            gone: !added.length
        },
        insChangedAt: opts.now
    };
}

export function resolveInputCard(pendingCard, currentSourceInfo) {
    if (!pendingCard) return null;
    const isIt = !!currentSourceInfo && currentSourceInfo.raw.toLowerCase() === pendingCard.key;
    const detail = pendingCard.gone
        ? (currentSourceInfo ? "Input on " + currentSourceInfo.title : "")
        : isIt ? "Microphone"
        : (currentSourceInfo ? "Input is still " + currentSourceInfo.title : "Microphone");
    return Object.assign({}, pendingCard, { detail });
}

export function shouldAnnounceInputSwitch(opts) {
    if (!opts.sourceName) return false;
    if (opts.now - opts.insChangedAt < INPUT_SETTLE_SUPPRESS_MS) return false;
    if (opts.quietSound) return false;
    return opts.sourceName !== opts.inWas;
}

export function resolveSoundClose(opts) {
    if (!opts.armed) return "none";
    if (opts.outName && opts.outName !== opts.soundOutWas) return "showVolume";
    if (opts.sourceName && opts.sourceName !== opts.soundInWas) return "inSwitch";
    return "none";
}
