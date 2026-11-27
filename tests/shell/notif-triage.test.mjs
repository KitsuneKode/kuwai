import { expect, test } from "bun:test";
import { triage, authAsk } from "../../shell/services/notifTriage.mjs";

const n = (o) => ({ app: "", summary: "", body: "", urgency: 1, actions: [], hints: {}, ...o });
const kitty = { appId: "kitty", class: "kitty", title: "~/Projects/rice" };

test("the shell's and HyDE's own status never reaches the list", () => {
    expect(triage(n({ app: "󰸉 Live Wallpaper", summary: "▶ 27-girl-behind-curtains.mp4" }))).toBe("drop");
    expect(triage(n({ app: "HyDE Alert", summary: "01-kami.jpg" }))).toBe("drop");
    expect(triage(n({ app: "Brightness", summary: "40%", hints: { value: 40 } }))).toBe("drop");
    expect(triage(n({ app: "HyDE Notify", summary: "muted" }))).toBe("drop");
    expect(triage(n({ app: "notify-send", summary: "x", hints: { "x-dunst-stack-tag": "volume" } }))).toBe("drop");
});

test("a failure in that status still shows once, and isn't kept", () => {
    expect(triage(n({ app: "HyDE Alert", summary: "Wallpaper not found" }))).toBe("keep");
    expect(triage(n({ app: "󰸉 Live Wallpaper", summary: "mpvpaper not installed" }))).toBe("toast");
});

test("the window you're in telling you what you just saw is dropped", () => {
    expect(triage(n({ app: "kitty", summary: "kitty", body: "Command make finished with status 0" }), kitty)).toBe("drop");
    expect(triage(n({ app: "kitty", summary: "kitty", body: "Command make finished with status 0" }), { appId: "zen", class: "zen", title: "x" })).toBe("keep");
});

test("a chat in the focused app about another conversation is kept", () => {
    const wa = { appId: "zapzap", class: "zapzap", title: "Ada — ZapZap" };
    expect(triage(n({ app: "ZapZap", summary: "Lin", body: "are you around?" }), wa)).toBe("keep");
    expect(triage(n({ app: "ZapZap", summary: "Ada", body: "ok" }), wa)).toBe("drop");
});

test("what needs you stays", () => {
    expect(triage(n({ app: "Gmail", summary: "Invoice", body: "due Friday" }), kitty)).toBe("keep");
    expect(triage(n({ app: "kitty", summary: "Kitty", body: "is asking for your password", actions: [{ identifier: "jump", text: "Jump" }] }), kitty)).toBe("keep");
    expect(triage(n({ app: "Battery", summary: "Battery 4%", urgency: 2, hints: { value: 4 } }))).toBe("keep");
});

test("a transient one toasts and is never written", () => {
    expect(triage(n({ app: "Doctor", summary: "Smoke test", transient: true }))).toBe("toast");
});

test("auth prompts are recognised for retiring once answered", () => {
    expect(authAsk({ app: "kitty", body: "sudo is asking for your password" })).toBe(true);
    expect(authAsk({ app: "kitty", body: "pkexec is waiting for a yes or a no" })).toBe(true);
    expect(authAsk({ app: "Gmail", body: "your password was changed" })).toBe(false);
});

test("a toast-only notification is never written to the history file", async () => {
    const { persisted } = await import("../../shell/services/notifUndo.mjs");
    const items = [{ id: 1, discard: false, fleeting: true }, { id: 2, discard: false }];
    expect(persisted(items, [], null, null).map(i => i.id)).toEqual([2]);
});
