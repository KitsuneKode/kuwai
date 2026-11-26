/**
 * What a waiting password prompt may say in the island. shell-auth writes one
 * of these (its describe()) to $XDG_RUNTIME_DIR/kuwai/auth-pending; any other
 * program running as you can write that file too, so the island shows only
 * these words, never what a file says. tests/shell/auth-words.test.mjs keeps
 * this list equal to describe()'s.
 * @type {string[]}
 */
export const WORDS = [
    "Install updates",
    "Replace config files",
    "Clean the package cache",
    "Run a command as administrator",
    "Install software",
    "Update the system",
    "Mount a drive",
    "Unlock an encrypted drive",
    "Change network settings",
    "Restart while others are signed in",
    "Shut down while others are signed in",
    "Manage a system service",
    "Change the date and time",
    "Rename this computer",
    "Administrator access"
];

/**
 * Is this process kuwai's password prompt: /usr/bin/qs on the pinned copy
 * (root's) or kuwai's own installed one, inside kuwai-auth.service?
 * @param {string} cmdline /proc/<pid>/cmdline
 * @param {string} [cgroup] /proc/<pid>/cgroup
 * @param {string} [stable] kuwai's installed shell-auth folder
 * @returns {boolean}
 */
export function isPrompt(cmdline, cgroup, stable) {
    const args = String(cmdline || "").split("\u0000");
    const at = args.indexOf("-p");
    const dir = at >= 0 ? String(args[at + 1] || "").replace(/\/+$/, "") : "";
    const known = dir === "/usr/local/share/kuwai/shell-auth" || (!!stable && dir === String(stable).replace(/\/+$/, ""));
    return args[0] === "/usr/bin/qs" && known && /\/kuwai-auth\.service$/m.test(String(cgroup || ""));
}

/**
 * The words to show, or "" when the file isn't the prompt's.
 * @param {string} text   the first line of auth-pending
 * @param {string} cmdline /proc/<pid>/cmdline of the process it names
 * @param {string} [cgroup] /proc/<pid>/cgroup
 * @param {string} [stable] kuwai's installed shell-auth folder
 * @returns {string}
 */
export function believed(text, cmdline, cgroup, stable) {
    const t = String(text || "").trim();
    return WORDS.indexOf(t) >= 0 && isPrompt(cmdline, cgroup, stable) ? t : "";
}
