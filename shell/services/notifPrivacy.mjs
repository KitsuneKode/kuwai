export const chatApps = /\b(zapzap|whatsapp|telegram|signal|discord|slack|element|messenger|beeper)\b/i;
export const mailApps = /\b(gmail|mail|thunderbird|betterbird|evolution|geary|kmail|mailspring|outlook|proton ?mail|tutanota|fastmail)\b/i;
export const textApps = /\b(sms|messages|kde ?connect|kdeconnect)\b/i;
export function personal(item) {
    const app = String(item.app || "");
    return chatApps.test(app) || mailApps.test(app) || textApps.test(app);
}

export const sensitiveText = /\b(password|passcode|passphrase|cvv|upi pin|atm pin|pin is|card (number|ending)|account (number|no))\b/i;

export function senders(list) {
    return String(list || "").split(",").map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
}

export function fromPrivateSender(item, list) {
    const who = (String(item.title || "") + " " + String(item.app || "")).toLowerCase();
    return senders(list).some(s => who.includes(s));
}

export function hidden(item, ctx) {
    if (!item) return false;
    if (ctx.sharing) return true;
    const urgent = item.severity === "critical" || item.severity === "warning";
    if (fromPrivateSender(item, ctx.privateSenders)) return true;
    if (sensitiveText.test(String(item.title || "") + " " + String(item.body || ""))) return true;
    const mine = personal(item);
    if (ctx.place === "lock") return mine && ctx.mode !== "never";
    if (urgent) return false;
    return mine && ctx.mode === "always";
}

export function toggleSender(list, name) {
    const n = String(name || "").trim();
    if (!n) return String(list || "");
    const have = senders(list);
    const parts = String(list || "").split(",").map(s => s.trim()).filter(s => s);
    return have.includes(n.toLowerCase()) ? parts.filter(s => s.toLowerCase() !== n.toLowerCase()).join(", ") : parts.concat([n]).join(", ");
}
