import { expect, test } from "bun:test";
import { functions } from "../helpers/qml.mjs";

function updates(over = {}) {
  const calls = [];
  const s = Object.assign({
    running: false, lowSpace: false, bin: "kuwai-update", plan: null, ownedRun: false, installPending: "", installAsk: "",
    reviews: { "localsend-bin": { head: "abc123" } }, approvedSha: {}, autoApproved: [], trusted: [], mutationError: "",
    mutationCurrent: null, starter: { command: [], running: false },
    resetRun() { calls.push("reset"); }, setExcluded() {}, selectable(n) { return !!this.approvedSha[n]; },
    enqueueMutation(job) { calls.push(job.args.join(" ")); this.mutationCurrent = job; },
    Island: { screen: "DP-3", open: (...a) => calls.push("open " + a.join(" ")) }
  }, over);
  s.calls = calls;
  return functions("shell/services/Updates.qml", ["requestInstall", "approveAndInstall", "installNew", "approve", "finishMutation"], s);
}

test("a new AUR package is approved at the commit you read, then built and installed alone", () => {
  const u = updates();
  u.approveAndInstall("localsend-bin");
  expect(u.calls).toEqual(["approve localsend-bin abc123"]);
  expect(u.starter.running).toBe(false);
  u.finishMutation(0);
  expect(u.approvedSha["localsend-bin"]).toBe("abc123");
  expect(u.starter.command).toEqual(["kuwai-update", "start", "--aur", "localsend-bin"]);
  expect(u.plan).toEqual({ repo: false, aur: ["localsend-bin"], flatpak: [] });
  expect(u.starter.running).toBe(true);
  expect(u.installPending).toBe("");
});

test("an approval that couldn't be saved installs nothing", () => {
  const u = updates();
  u.approveAndInstall("localsend-bin");
  u.finishMutation(1);
  expect(u.starter.running).toBe(false);
  expect(u.installPending).toBe("");
});

test("already approved or trusted: straight to the build; never while a run is on", () => {
  const u = updates({ approvedSha: { "localsend-bin": "abc123" } });
  u.approveAndInstall("localsend-bin");
  expect(u.starter.command).toEqual(["kuwai-update", "start", "--aur", "localsend-bin"]);
  const busy = updates({ running: true });
  busy.approveAndInstall("localsend-bin");
  expect(busy.calls).toEqual([]);
});

test("the launcher hands over only a package name", () => {
  const u = updates();
  u.requestInstall("localsend-bin; rm -rf ~");
  expect(u.installAsk).toBe("");
  u.requestInstall("localsend-bin");
  expect(u.installAsk).toBe("localsend-bin");
  expect(u.calls).toEqual(["open updates DP-3 pointer"]);
});
