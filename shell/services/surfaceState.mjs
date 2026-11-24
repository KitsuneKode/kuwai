export function createSurfaceState() {
    return {
        phase: "closed",
        armed: false,
        capturing: false,
        peeking: false,
        seq: 0
    };
}

export function surfaceOutputs(s) {
    const open = s.phase === "opening" || s.phase === "entering" || s.phase === "open";
    const folding = s.phase === "leaving";
    const mapped = s.phase !== "closed";
    return {
        open,
        folding,
        mapped,
        pendingBegin: s.phase === "opening",
        armed: open && s.armed,
        capturing: open && s.capturing,
        peeking: open && s.peeking,
        grabActive: open && s.armed && !s.capturing && !s.peeking,
        keyboardFocus: open && !s.capturing && !s.peeking
    };
}

export function stepSurface(state, event) {
    const s = state || createSurfaceState();
    const ev = event || { type: "" };
    switch (ev.type) {
    case "open": {
        const reopening = s.phase === "leaving";
        const seq = s.seq + 1;
        return {
            state: {
                phase: "opening",
                armed: false,
                capturing: false,
                peeking: !!ev.peeking,
                seq
            },
            effects: [
                { type: "startOpen", reopening, seq },
                { type: "scheduleBegin", seq }
            ]
        };
    }
    case "surfaceMapped": {
        if (s.phase !== "opening") return { state: s, effects: [] };
        if (ev.seq !== undefined && ev.seq !== s.seq) return { state: s, effects: [] };
        return {
            state: Object.assign({}, s, { phase: "entering" }),
            effects: [
                { type: "beginMotion", seq: s.seq },
                { type: "scheduleArm", seq: s.seq }
            ]
        };
    }
    case "armed": {
        if (s.phase !== "entering" && s.phase !== "opening") return { state: s, effects: [] };
        if (ev.seq !== undefined && ev.seq !== s.seq) return { state: s, effects: [] };
        return {
            state: Object.assign({}, s, { phase: "open", armed: true }),
            effects: []
        };
    }
    case "grabCleared": {
        const out = surfaceOutputs(s);
        if (!out.grabActive) return { state: s, effects: [] };
        if (ev.capturingTool) {
            return {
                state: Object.assign({}, s, { capturing: true }),
                effects: [{ type: "watchCapture", seq: s.seq }]
            };
        }
        return {
            state: s,
            effects: [{ type: "requestClose", seq: s.seq }]
        };
    }
    case "captureEnded": {
        if (!s.capturing) return { state: s, effects: [] };
        return {
            state: Object.assign({}, s, { capturing: false }),
            effects: [{ type: "refocus", seq: s.seq }]
        };
    }
    case "close": {
        if (s.phase === "closed" || s.phase === "leaving") {
            return {
                state: Object.assign({}, s, { armed: false, capturing: false, peeking: false }),
                effects: []
            };
        }
        const seq = s.seq + 1;
        return {
            state: {
                phase: "leaving",
                armed: false,
                capturing: false,
                peeking: false,
                seq
            },
            effects: [{ type: "startClose", seq }]
        };
    }
    case "foldDone": {
        if (s.phase !== "leaving") return { state: s, effects: [] };
        if (ev.seq !== undefined && ev.seq !== s.seq) return { state: s, effects: [] };
        return {
            state: Object.assign({}, s, { phase: "closed" }),
            effects: [{ type: "snapClosed", seq: s.seq }]
        };
    }
    default:
        return { state: s, effects: [] };
    }
}
