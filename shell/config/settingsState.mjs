export function createSettingsState() {
    return {
        generation: 0,
        readGeneration: 0,
        readBusy: true,
        needsRead: false,
        loaded: false,
        activeWrite: null,
        queue: []
    };
}

export function stepSettings(state, event) {
    const s = state || createSettingsState();
    const ev = event || { type: "" };
    switch (ev.type) {
    case "enqueue": {
        return {
            state: Object.assign({}, s, {
                generation: s.generation + 1,
                queue: s.queue.concat([ev.patch])
            }),
            effects: [{ type: "drain" }]
        };
    }
    case "fileChanged": {
        return {
            state: Object.assign({}, s, {
                generation: s.generation + 1,
                needsRead: true
            }),
            effects: [{ type: "scheduleRead" }]
        };
    }
    case "beginRead": {
        if (!s.needsRead || s.readBusy || s.activeWrite !== null || s.queue.length > 0) {
            return { state: s, effects: [] };
        }
        return {
            state: Object.assign({}, s, {
                needsRead: false,
                readBusy: true,
                readGeneration: s.generation
            }),
            effects: [{ type: "reloadFile", readGeneration: s.generation }]
        };
    }
    case "readCompleted": {
        const fresh = s.readGeneration === s.generation && s.activeWrite === null && s.queue.length === 0;
        const nextNeedsRead = fresh ? s.needsRead : true;
        const effects = [];
        if (fresh) {
            effects.push({ type: ev.ok ? "acceptDocument" : "recordLoadError", missing: !!ev.missing, text: ev.text || "" });
        }
        if (nextNeedsRead) effects.push({ type: "scheduleRead" });
        effects.push({ type: "drain" });
        return {
            state: Object.assign({}, s, {
                readBusy: false,
                loaded: true,
                needsRead: nextNeedsRead
            }),
            effects
        };
    }
    case "beginWrite": {
        if (!s.loaded || s.activeWrite !== null || s.queue.length === 0) {
            return { state: s, effects: [] };
        }
        const patch = s.queue[0];
        return {
            state: Object.assign({}, s, {
                activeWrite: patch,
                queue: s.queue.slice(1)
            }),
            effects: [{ type: "runWriter", patch }]
        };
    }
    case "writeCompleted": {
        const moreQueued = s.queue.length > 0;
        const ok = !!ev.ok;
        const effects = [];
        if (ok && !moreQueued) {
            effects.push({ type: "acceptDocument", text: ev.text || "" });
        } else if (!ok) {
            effects.push({ type: "recordWriteError", detail: ev.detail || "" });
        }
        const nextQueue = ok ? s.queue : [];
        const nextState = Object.assign({}, s, {
            activeWrite: null,
            queue: nextQueue,
            needsRead: true
        });
        if (nextQueue.length > 0) effects.push({ type: "drain" });
        else effects.push({ type: "scheduleRead" });
        return { state: nextState, effects };
    }
    default:
        return { state: s, effects: [] };
    }
}
