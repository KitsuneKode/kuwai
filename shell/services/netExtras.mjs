export function nmFields(line) {
  const out = [];
  let cur = "";
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
    if (c === ":") { out.push(cur); cur = ""; continue; }
    cur += c;
  }
  out.push(cur);
  return out;
}

export function vpns(text) {
  return String(text || "").split("\n").filter(l => l.trim()).map(nmFields)
    .filter(f => f.length >= 4 && (f[2] === "vpn" || f[2] === "wireguard"))
    .map(f => ({ name: f[0], uuid: f[1], kind: f[2] === "wireguard" ? "WireGuard" : "VPN", active: f[3] === "yes" }));
}

export function printers(text) {
  const list = [];
  let def = "";
  for (const l of String(text || "").split("\n")) {
    const p = l.match(/^printer (\S+) (?:is (idle|printing)|disabled)/);
    if (p) list.push({ name: p[1], state: p[2] || "disabled" });
    const d = l.match(/^system default destination: (\S+)/);
    if (d) def = d[1];
  }
  return list.map(p => Object.assign(p, { default: p.name === def }));
}

export function jobs(text) {
  return String(text || "").split("\n").map(l => l.match(/^(\S+-\d+)\s+(\S+)\s+(\d+)/)).filter(m => m)
    .map(m => ({ id: m[1], printer: m[1].replace(/-\d+$/, ""), user: m[2], bytes: Number(m[3]) }));
}

export function iwdStation(text) {
  const t = String(text || "");
  const net = t.match(/Connected network\s+(.+?)\s*$/m);
  const state = t.match(/^\s*State\s+(\S+)/m);
  return { network: net ? net[1] : "", state: state ? state[1] : "" };
}
