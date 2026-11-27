const CODE = /\b(code|token|otp|one[- ]time|verification|authenticator|yubi\w*|2fa|totp|pin)\b/i;
const FINGER = /\b(finger|swipe|sensor|reader|fingerprint)\b/i;

export function kind(message, visible) {
    if (visible) return "user";
    const m = String(message || "");
    return CODE.test(m) || FINGER.test(m) ? "challenge" : "password";
}

export function label(message) {
    return String(message || "Verification code").replace(/[:\s]+$/, "") || "Verification code";
}

export function note(message) {
    const m = String(message || "").replace(/\s+/g, " ").trim();
    if (!m) return "";
    return FINGER.test(m) ? "Touch the fingerprint sensor, or wait for the password" : m.slice(0, 96);
}

export function lockedMinutes(message) {
    const m = String(message || "");
    const left = m.match(/(\d+)\s+minutes?\s+left to unlock/i);
    if (left) return parseInt(left[1], 10);
    return /account is (temporarily )?locked/i.test(m) ? 1 : -1;
}
