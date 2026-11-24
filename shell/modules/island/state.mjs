export const MAX_DWELL_RETRIES = 6;

export function createIslandState() {
    return {
        hovered: false,
        grown: false,
        full: false,
        near: false,
        pushed: false,
        holdCompact: false,
        menus: 0,
        panelHere: false,
        armed: false,
        armSeq: 0,
        dwellRetries: 0,
        glanceDragging: false,
        peeked: false
    };
}

export function canGrow(s, flags) {
    const f = flags || {};
    return !!(
        s.hovered &&
        !s.panelHere &&
        !s.pushed &&
        !f.overPills &&
        !f.bannerHere &&
        !f.peekHere &&
        !f.deviceHere &&
        !f.agentMoment
    );
}

export function stepIsland(state, event) {
    const s = state || createIslandState();
    const ev = event || { type: "" };
    switch (ev.type) {
    case "hoverSync": {
        const h = !!ev.hovered;
        const holdCompact = h ? (s.hovered ? s.holdCompact : !!ev.compact) : false;
        const pushed = h ? s.pushed : false;
        return Object.assign({}, s, { hovered: h, holdCompact, pushed });
    }
    case "pushBack": {
        return Object.assign({}, s, { pushed: true, grown: false });
    }
    case "panelChanged": {
        const panelHere = !!ev.panelHere;
        const armSeq = s.armSeq + 1;
        if (panelHere) {
            return Object.assign({}, s, {
                panelHere: true,
                grown: false,
                pushed: false,
                armed: false,
                armSeq
            });
        }
        return Object.assign({}, s, {
            panelHere: false,
            armed: false,
            armSeq,
            grown: s.hovered ? true : s.grown
        });
    }
    case "armTick": {
        if (!s.panelHere || (ev.seq !== undefined && ev.seq !== s.armSeq)) return s;
        return Object.assign({}, s, { armed: true });
    }
    case "nearHover": {
        if (!ev.hovered) return Object.assign({}, s, { dwellRetries: 0 });
        return Object.assign({}, s, { dwellRetries: 0 });
    }
    case "nearDwellTick": {
        if (!ev.nearHovered || !ev.proximityAvailable) {
            return Object.assign({}, s, { dwellRetries: 0 });
        }
        if (ev.edgeSettled) {
            return Object.assign({}, s, { near: true, dwellRetries: 0 });
        }
        if (s.dwellRetries + 1 >= MAX_DWELL_RETRIES) {
            return Object.assign({}, s, { dwellRetries: MAX_DWELL_RETRIES });
        }
        return Object.assign({}, s, { dwellRetries: s.dwellRetries + 1 });
    }
    case "proximityAvailable": {
        if (ev.available) return s;
        return Object.assign({}, s, { near: false, dwellRetries: 0 });
    }
    case "peekChanged": {
        const peeked = !!ev.peeked;
        if (peeked && !s.panelHere) {
            return Object.assign({}, s, { peeked: true, pushed: false, grown: true });
        }
        if (!peeked && !s.hovered && s.menus === 0) {
            return Object.assign({}, s, { peeked: false, grown: false });
        }
        return Object.assign({}, s, { peeked });
    }
    case "leaveTick": {
        if (s.glanceDragging) return s;
        if (!s.hovered && s.menus === 0) {
            return Object.assign({}, s, { grown: false, pushed: false });
        }
        return s;
    }
    case "settled": {
        if (!s.grown) return Object.assign({}, s, { full: false });
        return s;
    }
    default:
        return s;
    }
}
