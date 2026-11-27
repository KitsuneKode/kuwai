const CODE = /\b(code|token|otp|one[- ]time|verification|authenticator|yubi\w*|2fa|totp|pin)\b/i;
const FINGER = /\b(finger|swipe|sensor|reader|fingerprint)\b/i;

export function kind(message, visible) {
    if (visible) return "user";
    return CODE.test(String(message || "")) ? "challenge" : "password";
}

export function label(message) {
    return String(message || "Verification code").replace(/[:\s]+$/, "") || "Verification code";
}

export function note(message) {
    const m = String(message || "").replace(/\s+/g, " ").trim();
    if (!m) return "";
    return FINGER.test(m) ? "Touch the fingerprint sensor, or wait for the password" : m.slice(0, 96);
}
