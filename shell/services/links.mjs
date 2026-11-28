// Links that come from outside the shell (an Arch news item, an AUR page, a
// model's answer, a feed) open only when they are the web or mail: never
// file://, an app's own scheme (vscode://, t3code://) or javascript:. Every
// surface that opens such a link asks here first; nothing hands one to
// xdg-open unchecked (tests/security/test_links.py).
//
//   import "../../services/links.mjs" as Links
//   if (Links.safeLink(url)) Qt.openUrlExternally(url)
/** @param {unknown} url */
export function safeLink(url) { return /^(https?:\/\/|mailto:)/i.test(String(url || "").trim()); }

// The link if it may be opened, else "" (for a button's `enabled`).
/** @param {unknown} url */
export function webLink(url) { return safeLink(url) ? String(url).trim() : ""; }
