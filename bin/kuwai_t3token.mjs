import { readFileSync, lstatSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const KINDS = {
  read: { env: "KUWAI_T3_TOKEN", key: "t3-token", file: "t3-token" },
  operate: { env: "KUWAI_T3_OPERATE_TOKEN", key: "t3-operate-token", file: "t3-operate-token" },
};

export function privateText(path) {
  try {
    const st = lstatSync(path);
    if (!st.isFile() || st.uid !== process.getuid() || (st.mode & 0o077)) return "";
    return readFileSync(path, "utf8").trim();
  } catch { return ""; }
}

function keyring(key) {
  try {
    return execFileSync("secret-tool", ["lookup", "service", "kuwai", "key", key], {
      encoding: "utf8", timeout: 1500, stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch { return ""; }
}

export function t3Token(kind = "read") {
  const k = KINDS[kind];
  const state = process.env.XDG_STATE_HOME || join(process.env.HOME || "", ".local/state");
  const own = (process.env[k.env] || "").trim() || keyring(k.key) || privateText(join(state, "kuwai", k.file));
  if (own || kind === "read") return own;
  return t3Token("read");
}
