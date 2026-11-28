import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import * as M from "../../shell/services/meeting.mjs";

const fixture = name => readFileSync(new URL("../ui/fixtures/meeting/" + name, import.meta.url), "utf8");
const events = fixture("feed.ndjson").split("\n").map(M.parseLine).filter(e => e);
const upTo = n => events.slice(0, n).reduce(M.apply, M.empty());

test("hello is the whole picture: status, title, start and every line so far", () => {
  const s = upTo(1);
  expect(s.status).toBe("recording");
  expect(s.title).toBe("Release sync");
  expect(s.startedAt).toBe(Date.parse("2026-11-11T15:00:04Z"));
  expect(s.segments.map(x => x.id)).toEqual([0, 1]);
  expect(s.notice).toBe(true);
  expect(M.active(s.status)).toBe(true);
});

test("segments of two tracks land in spoken order, not arrival order", () => {
  const s = upTo(5);
  expect(s.segments.map(x => x.id)).toEqual([0, 1, 2, 3, 4]);
  expect(s.segments[2].who).toBe("Dana");
  expect(M.latest(s.segments).id).toBe(4);
});

test("an updated line replaces the old copy, a deleted one goes, a rename and the notice follow", () => {
  const s = upTo(12);
  expect(s.segments.filter(x => x.id === 4).length).toBe(1);
  expect(s.segments.find(x => x.id === 4).note).toEqual({ text: "Known issue for the notes", highlight: true });
  expect(s.segments.some(x => x.id === 6)).toBe(false);
  expect(s.title).toBe("Pete <> Chad Bi-Weekly");
  expect(s.notice).toBe(false);
});

test("levels map dBFS onto 0..1 the way the contract says, silence and missing tracks apart", () => {
  const s = upTo(2);
  expect(s.mic).toBeCloseTo((-23.4 + 60) / 60, 5);
  expect(s.loopback).toBeCloseTo(19 / 60, 5);
  expect(M.meter(-100)).toBe(0);
  expect(M.meter(5)).toBe(1);
  expect(M.meter(null)).toBe(-1);
  expect(M.apply(s, { event: "levels", soundcheck: true, mic: 0 })).toBe(s);
});

test("pause and resume move the phase; idle ends it and keeps what it was", () => {
  expect(M.phase(upTo(9).status)).toBe("paused");
  expect(M.phase(upTo(10).status)).toBe("live");
  expect(M.phase(upTo(13).status)).toBe("ending");
  const done = upTo(14);
  expect(done.status).toBe("idle");
  expect(M.active(done.status)).toBe(false);
  expect(done.lastId).toBe("a32baa9b-b9df-4051-8830-b422d21495ed");
  expect(done.lastTitle).toBe("Pete <> Chad Bi-Weekly");
  expect(done.segments.length).toBe(5);
});

test("the reader waits for the summary after a meeting, then lets go", () => {
  const summarizing = upTo(15);
  expect(summarizing.summarizing).toBe("a32baa9b-b9df-4051-8830-b422d21495ed");
  expect(M.feedDone(summarizing, summarizing.endedAt + 1000)).toBe(false);
  expect(M.feedDone(summarizing, summarizing.endedAt + M.SUMMARY_WAIT_MS + 1)).toBe(true);
  const ready = upTo(16);
  expect(ready.summarizing).toBe("");
  expect(ready.summary.actions).toEqual([{ text: "Draft the release notes", who: "Dana", done: false }, { text: "Tag the release", who: "You", done: false }]);
  expect(M.feedDone(ready, Date.now())).toBe(true);
  expect(M.feedDone(upTo(1), Date.now())).toBe(false);
});

test("speakers count once each, you first; a speaker rename carries every line", () => {
  const s = upTo(5);
  expect(M.speakers(s.segments)).toEqual([{ name: "You", lines: 3, you: true }, { name: "Dana", lines: 2, you: false }]);
  const r = M.apply(M.apply(M.empty(), { event: "hello", status: "recording", meeting_id: "x", segments: [{ id: 0, start_ms: 0, text: "hi", source: "loopback", speaker_id: "Remote" }] }), { event: "speaker_renamed", from: "Remote", to: "Remote 1" });
  expect(r.segments[0].who).toBe("Remote 1");
});

test("the island's line: who and what, one line, and nothing while the screen is shared", () => {
  const s = upTo(5);
  expect(M.line(M.latest(s.segments), {})).toBe("Dana: Only one. The restart banner stays visible after the daemon restarts.");
  expect(M.line(M.latest(s.segments), { sharing: true })).toBe("");
  expect(M.line(M.latest(s.segments), { max: 20 }).endsWith("…")).toBe(true);
  expect(M.oneLine("a\n\n  b")).toBe("a b");
});

test("dictation takes the stage from a meeting; the meeting never takes it from dictation", () => {
  expect(M.stageOf(true, true)).toBe("vox");
  expect(M.stageOf(true, false)).toBe("meet");
  expect(M.stageOf(false, false)).toBe("");
});

test("broken lines and unknown events change nothing", () => {
  const s = upTo(3);
  expect(M.parseLine("not json")).toBe(null);
  expect(M.parseLine("")).toBe(null);
  expect(M.apply(s, { event: "playback", state: "playing" })).toBe(s);
  expect(M.apply(s, null)).toBe(s);
  expect(M.apply(s, { event: "status", status: "exploded" }).status).toBe("recording");
});

test("the daemon's hint file is two lines; anything else reads as idle", () => {
  expect(M.hint("recording\nabc")).toEqual({ status: "recording", id: "abc" });
  expect(M.hint("idle")).toEqual({ status: "idle", id: "" });
  expect(M.hint("")).toEqual({ status: "idle", id: "" });
  expect(M.hint("weird\nabc").status).toBe("idle");
});

test("clocks and lengths", () => {
  expect(M.clock(0)).toBe("0:00");
  expect(M.clock(724)).toBe("12:04");
  expect(M.clock(3725)).toBe("1:02:05");
  expect(M.length(1868)).toBe("31 min");
  expect(M.length(40)).toBe("1 min");
  expect(M.length(20)).toBe("Under a minute");
  expect(M.length(3900)).toBe("1 h 5 min");
  expect(M.length(0)).toBe("");
});

test("the list: newest first as voxtype gives it, empty titles kept empty, junk refused", () => {
  const rows = M.parseList(fixture("list.json"));
  expect(rows.length).toBe(2);
  expect(rows[0]).toMatchObject({ title: "Release sync", secs: 1868, speakers: 3, hasSummary: true });
  expect(rows[1].title).toBe("");
  expect(M.titleOr(rows[1], "Meeting")).toBe("Meeting");
  expect(M.rowSub(rows[0], { when: "Tue 11 Nov" })).toBe("Tue 11 Nov · 3 speakers");
  expect(M.rowSub(rows[1], { when: "Mon" })).toBe("Mon · Didn't finish");
  expect(M.parseList("{}")).toBe(null);
  expect(M.parseList("nope")).toBe(null);
  expect(M.parseList("[]")).toEqual([]);
});

test("show: summary, notes and the transcript without hidden lines", () => {
  const m = M.parseShow(fixture("show.json"));
  expect(m.title).toBe("Release sync");
  expect(m.notes).toBe("Tag at 10 tomorrow.");
  expect(m.segments.map(x => x.id)).toEqual([0]);
  expect(m.summary.actions[0].who).toBe("Dana");
  expect(M.parseShow("[]")).toBe(null);
});

test("a call link is found in an event's text, only over https and only for call services", () => {
  expect(M.callLink("Join: https://meet.google.com/abc-defg-hij.")).toBe("https://meet.google.com/abc-defg-hij");
  expect(M.callLink("https://us02web.zoom.us/j/123?pwd=x")).toBe("https://us02web.zoom.us/j/123?pwd=x");
  expect(M.callLink("<https://teams.microsoft.com/l/meetup-join/19%3a>")).toBe("https://teams.microsoft.com/l/meetup-join/19%3a");
  expect(M.callLink("http://meet.google.com/abc")).toBe("");
  expect(M.callLink("https://evil.example/meet.google.com")).toBe("");
  expect(M.callLink("https://meet.google.com.evil.example/x")).toBe("");
  expect(M.callLink("Room 4")).toBe("");
});

test("the calendar offer: an event with a call, from a minute before to five after its start, once", () => {
  const t = Date.parse("2026-11-28T10:00:00Z");
  const ev = { start: t, end: t + 1800000, title: "Weekly sync", allDay: false, call: "https://meet.google.com/x" };
  expect(M.offerFor([ev], t - 2 * 60000, {})).toBe(null);
  expect(M.offerFor([ev], t - 30000, {})).toMatchObject({ title: "Weekly sync", url: "https://meet.google.com/x", from: "calendar" });
  expect(M.offerFor([ev], t + 4 * 60000, {})).not.toBe(null);
  expect(M.offerFor([ev], t + 6 * 60000, {})).toBe(null);
  expect(M.offerFor([ev], t, { offered: { [M.offerKey(ev)]: t } })).toBe(null);
  expect(M.offerFor([ev], t, { active: true })).toBe(null);
  expect(M.offerFor([ev], t, { off: true })).toBe(null);
  expect(M.offerFor([Object.assign({}, ev, { call: "" })], t, {})).toBe(null);
  expect(M.offerFor([Object.assign({}, ev, { allDay: true })], t, {})).toBe(null);
  expect(M.forgetOffers({ a: t - M.FORGET_OFFERS_MS - 1, b: t }, t)).toEqual({ b: t });
});

test("call detection: the daemon prompting itself wins; a dry run's prompt is read word for word", () => {
  const daemon = "Meeting detection in the daemon: on (default on Omarchy)\nevidence: x\nwould prompt: Record \"Google Meet call\"? (Google Meet)\n";
  expect(M.parseSuggest(daemon)).toEqual({ known: true, daemon: true, enabled: true, prompt: { title: "Google Meet call", app: "Google Meet" } });
  const quiet = "Meeting detection in the daemon: off (default off outside Omarchy; set [meeting.detect] enabled = true)\nwould prompt: Record \"Budget review\"? (Microsoft Teams)";
  expect(M.parseSuggest(quiet)).toMatchObject({ daemon: false, enabled: true, prompt: { title: "Budget review", app: "Microsoft Teams" } });
  const off = "Meeting detection in the daemon: off: [meeting] enabled = false\nwindows: 3 from Hyprland\nmic streams: 0";
  expect(M.parseSuggest(off)).toMatchObject({ daemon: false, enabled: false, prompt: null });
  expect(M.parseSuggest("")).toMatchObject({ known: false, prompt: null });
});

test("a meeting-view request is acted on only while fresh", () => {
  const now = 1794440137340;
  const body = JSON.stringify({ ask: null, ask_id: null, meeting_id: "latest", open: true, requested_at: now - 1000, tab: "notes", window: "expand" });
  expect(M.viewRequest(body, now)).toEqual({ meeting: "latest", tab: "notes", open: true, minimize: false });
  expect(M.viewRequest(body, now + M.REQUEST_STALE_MS + 1)).toBe(null);
  expect(M.viewRequest(JSON.stringify({ ask_id: "q", requested_at: now }), now).tab).toBe("ask");
  expect(M.viewRequest("garbage", now)).toBe(null);
  expect(JSON.parse(M.viewState(true, 42, 1794434659.7))).toEqual({ visible: true, minimized: false, host: "kuwai", pid: 42, updated_at: 1794434659 });
});

test("an exported file is named by its day and title, with nothing that reaches another folder", () => {
  const t = new Date(2026, 10, 11, 15, 0).getTime();
  expect(M.fileName("Release sync", t)).toBe("2026-11-11 Release sync.md");
  expect(M.fileName("../../etc/passwd", t)).toBe("2026-11-11 etc passwd.md");
  expect(M.fileName("", 0)).toBe("Meeting.md");
  expect(M.fileName("a\u0000b\nc", t)).toBe("2026-11-11 a b c.md");
});

test("delete takes two presses on the same meeting", () => {
  let r = M.arm("", "a");
  expect(r).toEqual({ armed: "a", fire: false });
  r = M.arm(r.armed, "b");
  expect(r).toEqual({ armed: "b", fire: false });
  expect(M.arm(r.armed, "b")).toEqual({ armed: "", fire: true });
});

test("a silent track is said in words, without the config command", () => {
  expect(M.trackWords("track_not_transcribed", "Your microphone has sound, but nothing you say is transcribed: … voxtype config set meeting.audio.vad_threshold 0.01")).toBe("Your microphone has sound, but none of it is in the transcript yet.");
  expect(M.trackWords("local_failed", "x")).toBe("");
});

test("the calendar keeps each event's call link, from its location, description or conference field", async () => {
  const { functions } = await import("../helpers/qml.mjs");
  const cal = functions("shell/services/Calendar.qml", ["parseTime", "icsText", "parse"], { MeetingLogic: M });
  const soon = new Date(Date.now() + 3600000);
  const two = n => String(n).padStart(2, "0");
  const at = soon.getUTCFullYear() + two(soon.getUTCMonth() + 1) + two(soon.getUTCDate()) + "T" + two(soon.getUTCHours()) + "0000Z";
  const ics = ["BEGIN:VEVENT", "DTSTART:" + at, "SUMMARY:Weekly sync", "DESCRIPTION:Join with Google Meet: https://meet.google.com/abc-defg-hij\\nOr dial in", "END:VEVENT",
               "BEGIN:VEVENT", "DTSTART:" + at, "SUMMARY:Dentist", "LOCATION:Main street 4", "END:VEVENT",
               "BEGIN:VEVENT", "DTSTART:" + at, "SUMMARY:Teams", "X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/19%3ameeting", "END:VEVENT"].join("\n");
  const events = cal.parse(ics);
  expect(events.find(e => e.title === "Weekly sync").call).toBe("https://meet.google.com/abc-defg-hij");
  expect(events.find(e => e.title === "Dentist").call).toBe("");
  expect(events.find(e => e.title === "Teams").call).toBe("https://teams.microsoft.com/l/meetup-join/19%3ameeting");
});
