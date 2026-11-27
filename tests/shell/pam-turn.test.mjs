import { expect, test } from "bun:test";
import { kind, label, note, lockedMinutes } from "../../shell/services/pamTurn.mjs";

test("the password goes only to a password prompt", () => {
    expect(kind("Password: ", false)).toBe("password");
    expect(kind("Passwort: ", false)).toBe("password");
    expect(kind("", false)).toBe("password");
    expect(kind("Verification code: ", false)).toBe("challenge");
    expect(kind("Enter PIN for YubiKey", false)).toBe("challenge");
    expect(kind("One-time password (OATH) for `me':", false)).toBe("challenge");
    expect(kind("login:", true)).toBe("user");
});

test("a challenge shows what PAM asked", () => {
    expect(label("Verification code: ")).toBe("Verification code");
    expect(label("")).toBe("Verification code");
});

test("a fingerprint prompt says what to do", () => {
    expect(note("Place your finger on the fingerprint reader")).toBe("Touch the fingerprint sensor, or wait for the password");
    expect(note("")).toBe("");
});

test("a finger prompt never takes the password", () => {
    expect(kind("Swipe your finger across the reader", false)).toBe("challenge");
});

test("pam_faillock's lockout message gives the wait", () => {
    expect(lockedMinutes("The account is locked due to 3 failed logins.")).toBe(1);
    expect(lockedMinutes("(9 minutes left to unlock)")).toBe(9);
    expect(lockedMinutes("Password: ")).toBe(-1);
});
