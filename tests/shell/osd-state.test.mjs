import { describe, expect, test } from "bun:test";
import {
    createOsdState,
    diffExternalInputs,
    isFreshNode,
    isUnplugged,
    resolveInputCard,
    resolveOutputSwitch,
    resolveSoundClose,
    shouldAnnounceInputSwitch,
    shouldFireZeroHold,
    shouldShowMute,
    updateFirstSeen,
    volumeDecision
} from "../../shell/modules/osd/state.mjs";

describe("osd audio/hotplug state machine", () => {
    test("volume and mute changes settle cleanly across sink switches and unplug zero-drops", () => {
        const s = createOsdState();
        expect(volumeDecision(s, 0.5, 1000)).toBe("ignore");
        s.armed = true;
        s.sinkSwitchedAt = 1000;
        expect(volumeDecision(s, 0.5, 1500)).toBe("ignore");
        expect(shouldShowMute(s, 1500)).toBe(false);
        expect(volumeDecision(s, 0, 1700)).toBe("holdZero");
        expect(volumeDecision(s, 0.4, 1700)).toBe("show");
        expect(shouldShowMute(s, 1700)).toBe(true);
        expect(shouldFireZeroHold(s, 0, 1350)).toBe(false);
        expect(shouldFireZeroHold(s, 0, 1500)).toBe(true);
        expect(shouldFireZeroHold(s, 0.2, 1500)).toBe(false);
    });

    test("cold-start nodes are not treated as fresh hotplugs, while post-arm nodes are", () => {
        let seen = updateFirstSeen({}, ["usb-dac"], false, 5000);
        expect(seen["usb-dac"]).toBe(1);
        expect(isFreshNode(seen, "usb-dac", 5000)).toBe(true);
        expect(isFreshNode(seen, "usb-dac", 20000)).toBe(false);

        seen = updateFirstSeen(seen, ["usb-dac", "new-dac"], true, 25000);
        expect(isFreshNode(seen, "new-dac", 26000)).toBe(true);
        expect(isFreshNode(seen, "usb-dac", 26000)).toBe(false);
    });

    test("USB DAC unplug + new DAC plug resolves gone card and connected card without races", () => {
        const left = { name: "dac-old", wired: true };
        expect(isUnplugged(left, "dac-new", ["dac-new", "speakers"])).toBe(true);
        expect(isUnplugged(left, "dac-new", ["dac-old", "dac-new"])).toBe(false);

        const res = resolveOutputSwitch({
            bar: "island",
            leftOut: left,
            currentOut: { name: "dac-new", wired: true },
            currentOutName: "dac-new",
            nodeNames: ["dac-new", "speakers"],
            firstSeen: { "dac-new": 10000 },
            now: 11000,
            quietSound: false
        });
        expect(res).toEqual({ notifyGone: true, action: "inputCard" });

        const quietRes = resolveOutputSwitch({
            bar: "island",
            leftOut: left,
            currentOut: { name: "dac-new", wired: true },
            currentOutName: "dac-new",
            nodeNames: ["dac-new", "speakers"],
            firstSeen: { "dac-new": 10000 },
            now: 11000,
            quietSound: true
        });
        expect(quietRes).toEqual({ notifyGone: true, action: "showVolume" });
    });

    test("external mic diff records baseline before arm, announces add/remove after arm, and suppresses duplicate switch", () => {
        const usb = [{ name: "mic-1", key: "usb mic", title: "USB Mic", image: "" }];
        const boot = diffExternalInputs([], usb, { armed: false, bar: "island", now: 1000, externalMicGlyph: "M" });
        expect(boot.baselineKeys).toEqual(["usb mic"]);
        expect(boot.pendingCard).toBeNull();

        const added = diffExternalInputs(
            boot.knownIns,
            usb.concat([{ name: "mic-2", key: "podmic", title: "PodMic", image: "p.png" }]),
            { armed: true, bar: "island", now: 5000, externalMicGlyph: "M" }
        );
        expect(added.pendingCard).toMatchObject({ key: "podmic", gone: false, link: "usb" });
        const card = resolveInputCard(added.pendingCard, { raw: "PodMic", title: "PodMic" });
        expect(card.detail).toBe("Microphone");

        expect(shouldAnnounceInputSwitch({
            sourceName: "mic-2", inWas: "mic-1", now: 6000, insChangedAt: added.insChangedAt, quietSound: false
        })).toBe(false);
        expect(shouldAnnounceInputSwitch({
            sourceName: "mic-2", inWas: "mic-1", now: 8000, insChangedAt: added.insChangedAt, quietSound: false
        })).toBe(true);
    });

    test("sound panel close reports whichever route changed", () => {
        expect(resolveSoundClose({ armed: false, outName: "b", soundOutWas: "a", sourceName: "x", soundInWas: "x" })).toBe("none");
        expect(resolveSoundClose({ armed: true, outName: "b", soundOutWas: "a", sourceName: "y", soundInWas: "x" })).toBe("showVolume");
        expect(resolveSoundClose({ armed: true, outName: "a", soundOutWas: "a", sourceName: "y", soundInWas: "x" })).toBe("inSwitch");
        expect(resolveSoundClose({ armed: true, outName: "a", soundOutWas: "a", sourceName: "x", soundInWas: "x" })).toBe("none");
    });
});
