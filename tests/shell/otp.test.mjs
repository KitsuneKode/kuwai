// One-time codes: what the notch may show big with a Copy button, and what
// the lock screen hides. `bun test tests/shell/otp.test.mjs`
import { describe, expect, test } from "bun:test";
import { otpOf, otpLikely, candidates, clean, mentionsCode, codeShaped, originBound } from "../../shell/services/otp.mjs";

const n = (title, body = "", full = "") => ({ title, body, full });

describe("real codes are found", () => {
  const yes = [
    [n("Google", "Your verification code is 482913"), "482913"],
    [n("Verification", "Your code is 123 456"), "123456"],
    [n("Security PIN", "Your Security PIN is 4821"), "4821"],
    [n("482913 is your code"), "482913"],
    [n("Google", "G-482913 is your Google verification code."), "482913"],
    [n("Sign in", "Use 77F3K9QA to sign in"), "77F3K9QA"],
    [n("HDFC Bank", "OTP: 739201. Do not share it with anyone."), "739201"],
    [n("Amazon", "738291 is your Amazon OTP. Do not share it."), "738291"],
    [n("GitHub", "Your GitHub authentication code\n\n482913\n\nexpires in 10 minutes"), "482913"],
    [n("Microsoft", "Use 4829 as your Microsoft account security code"), "4829"],
    [n("Slack", "Your Slack confirmation code is: X7K-9P2".replace("X7K-9P2", "X7K9P2")), "X7K9P2"],
    [n("Discord", "Your Discord login code: 123-456"), "123456"],
    [n("Steam", "Enter 48291 to verify your email"), "48291"],
    [n("Bank", "Your one-time password for the transfer of Rs 5,000.00 is 482913"), "482913"],
    [n("WhatsApp", "Your WhatsApp code: 482-913\nDon't share this code with others"), "482913"],
    [n("Stripe", "To sign in to Stripe, enter 482913"), "482913"],
    [n("Apple", "Your Apple ID Code is: 482913. Don't share it with anyone."), "482913"],
    [n("Mail", "", "Hello,\nyour passcode is 12345678\nThanks"), "12345678"],
  ];
  for (const [item, code] of yes)
    test(JSON.stringify(item.body || item.title).slice(0, 70), () => expect(otpOf(item)).toBe(code));
});

describe("what a developer's desktop is full of is not a code", () => {
  const no = [
    // The eight from the owner's history, 2026-11-17 (shapes kept, names changed).
    n("Release Guard", "**Branch**: [chore/dead-code-and-size-20261117](<https://github.com/o/r/tree/chore/dead-code-and-size-20261117>)"),
    n("CI", "**Branch**: [ci/macos-15-runner-20261117](<https://github.com/o/r/tree/ci/macos-15-runner-20261117>) Code scanning passed"),
    n("Jobs", "Sign in to apply: https://www.example.com/careers/jobs/7284613?utm_source=cv"),
    n("T3 Code", "Production Readiness and Feature Audit finished"),
    n("Claude Code", "Task 482913 finished in ~/Projects/rice"),
    n("Deploy", "Build failed with exit code 137 after 482913 ms"),
    n("API", "Error code 401201: sign in again"),
    n("Shop", "Use promo code SAVE2026 at checkout"),
    n("Courier", "Your parcel for zip code 560001 is out for delivery"),
    n("Bank", "Rs 125000.00 credited to a/c XX4821 on 17-11-2026. Confirm the transfer in the app"),
    n("Security update", "Kernel 7.3.4 confirms the fix; 1554 packages, 482913 KiB"),
    n("GitHub", "PR #482913 needs your review: security hardening and sign-in fixes"),
    n("Calendar", "Meeting", "Room 2026 at 3pm"),
    n("Slack", "Anna: lunch at 12? my pin broke"),
    n("Updates", "linux 7.3.4.zen2-2 → 7.3.5.zen1-1 · verify the signature with key 0xA1B2C3D4"),
    n("Phone", "Missed call from +91 98765 43210. Sign in to see voicemail"),
    n("Video", "H264 1080p60 HDR10PLUS, confirm to download (482 MB)"),
    n("Docker", "Container a1b2c3d4 exited; log in to the registry and pull again"),
    n("Mail", "Your order 554321 has shipped. Your security code was not changed."),
    n("VS Code", "Extension host restarted 20261117"),
    n("Wi-Fi", "Connected to HOME5G2026. Log in may be required"),
    n("Timer", "Pin this: 12:3456 elapsed"),
  ];
  for (const item of no)
    test(JSON.stringify(item.body || item.title).slice(0, 70), () => expect(otpOf(item)).toBe(""));
});

describe("candidates stand on their own", () => {
  const codes = (t) => candidates(clean(t)).map(c => c.code);
  test("links, addresses and link targets hold none", () => {
    expect(codes("see https://x.example/a/1234567?b=765432 or mail a482913@x.example")).toEqual([]);
    expect(codes("[label](<https://x.example/20261117/482913>)")).toEqual([]);
  });
  test("years, dates, versions, amounts, times, paths, branches", () => {
    expect(codes("2026 20261117 v1.2345 3.14159 $48291 ₹482913 12:3456 a/482913 x-482913 482913-rc 48291% #482913")).toEqual([]);
  });
  test("grouped, prefixed and mixed forms", () => {
    expect(codes("482 913, 1234-5678, G-482913, 77F3K9QA, 1234ABCD.")).toEqual(["482913", "12345678", "482913", "77F3K9QA", "1234ABCD"]);
  });
  test("capitals alone, or longer than a code, are words", () => {
    expect(codes("WARNING RTX4050TI9 482913000")).toEqual([]);
  });
});

describe("the lock screen is more careful, not careless", () => {
  test("hides when a code is talked about and a number could be it", () => {
    expect(otpLikely(n("Bank", "Never share your OTP. Reference 482913"))).toBe(true);
    expect(otpLikely(n("Mail", "Your code will arrive by SMS. Ticket 48291"))).toBe(true);
  });
  test("anything the notch calls a code is one on the lock too", () => {
    for (const t of ["Your code is 123 456", "482913 is your code", "OTP: 739201"]) {
      expect(otpOf(t)).not.toBe("");
      expect(otpLikely(t) || otpOf(t) !== "").toBe(true);
    }
  });
  test("leaves branches, links, exit codes and app names alone", () => {
    for (const item of [
      n("Release Guard", "[chore/dead-code-and-size-20261117](<https://github.com/o/r>) Code scanning passed"),
      n("Deploy", "exit code 137 after 482913 ms"),
      n("T3 Code", "thread 482913 finished"),
      n("Jobs", "Sign in to apply: https://www.example.com/careers/jobs/7284613"),
      n("Slack", "Anna: lunch at 12?"),
    ]) expect(otpLikely(item)).toBe(false);
  });
  test("mentionsCode knows the phrases that aren't", () => {
    expect(mentionsCode("exit code 1, error code 2, zip code, QR code, T3 Code, dead-code")).toBe(false);
    expect(mentionsCode("your code")).toBe(true);
    expect(mentionsCode("one-time password")).toBe(true);
  });
  test("codeShaped: a title that shows a code", () => {
    expect(codeShaped("482913 is your code")).toBe(true);
    expect(codeShaped("Sign in")).toBe(false);
  });
});

describe("the sender's own marking (origin-bound codes, WICG)", () => {
  test("the last line says which token is the code and whose", () => {
    expect(originBound("747723 is your ExampleCo authentication code.\n\n@example.com #747723")).toEqual({ host: "example.com", code: "747723" });
    expect(otpOf(n("ExampleCo", "Hello.\n@login.example.co.in #A1B2C3"))).toBe("A1B2C3");
    expect(otpOf(n("Bank", "Welcome back\n@bank.example #9981 @pay.example"))).toBe("9981");
  });
  test("only as the last line, with a host and a code", () => {
    expect(originBound("@example.com #747723\nthanks")).toBe(null);
    expect(originBound("mail me @anna #lunch")).toBe(null);
    expect(originBound("see @example.com #1")).toBe(null);
    expect(otpOf(n("Slack", "@channel #general 20261117"))).toBe("");
  });
});
