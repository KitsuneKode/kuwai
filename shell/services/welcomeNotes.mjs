export function notesFor(text, version, max = 8) {
  const lines = String(text || "").split("\n");
  const start = lines.findIndex(l => new RegExp("^## " + version.replace(/\./g, "\\.") + "(\\s|$)").test(l));
  if (start < 0) return [];
  const out = [];
  let cur = null, group = "";
  const plain = s => s.replace(/`([^`]*)`/g, "$1").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/\*\*([^*]*)\*\*/g, "$1").trim();
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i];
    if (/^## /.test(l)) break;
    const h = l.match(/^### (.*)/);
    if (h) { group = plain(h[1]); cur = null; continue; }
    const b = l.match(/^- (.*)/);
    if (b) { cur = { group, text: plain(b[1]) }; out.push(cur); continue; }
    if (cur && /^\s{2,}\S/.test(l)) cur.text = plain(cur.text + " " + l.trim());
    else if (!l.trim()) cur = null;
  }
  return out.slice(0, max);
}

export function due(seen, version) {
  if (!version) return "";
  if (!seen) return "first";
  const p = v => String(v).split(".").map(n => parseInt(n, 10) || 0);
  const a = p(version), b = p(seen);
  for (let i = 0; i < Math.max(a.length, b.length); i++) if ((a[i] || 0) !== (b[i] || 0)) return (a[i] || 0) > (b[i] || 0) ? "new" : "";
  return "";
}
