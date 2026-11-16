.pragma library
// Pure contract logic. settings-schema.json is the authored source of truth.
function entry(schema, key) { return schema.settings.find(x => x.key === key); }
function valid(e, v) {
    if (!e) return false;
    if (e.type === "boolean" && typeof v !== "boolean") return false;
    if ((e.type === "integer" || e.type === "number") && (typeof v !== "number" || !Number.isFinite(v))) return false;
    if (e.type === "integer" && !Number.isInteger(v)) return false;
    if (e.type === "string" && typeof v !== "string") return false;
    if (e.type === "array" && !Array.isArray(v)) return false;
    if (e.enum && !e.enum.includes(v)) return false;
    if ((e.min !== undefined && v < e.min) || (e.max !== undefined && v > e.max)) return false;
    if (e.type === "string" && (Array.from(v).length > (e.maxLength || 512) || (e.pattern && !(new RegExp(e.pattern)).test(v)))) return false;
    if (e.type === "array" && (v.length > (e.maxItems || 256) || v.some(x => typeof x !== "string" || Array.from(x).length > (e.maxLength || 512)))) return false;
    return true;
}
function defaults(schema) {
    const result = Object.create(null);
    for (const e of schema.settings) result[e.key] = e.default;
    return result;
}
function parse(schema, text) {
    const doc = JSON.parse(text);
    if (!doc || Array.isArray(doc) || typeof doc !== "object") throw new Error("Settings must be a JSON object");
    const version = doc._schemaVersion === undefined ? 0 : doc._schemaVersion;
    if (!Number.isInteger(version) || version < 0 || version > schema.version) throw new Error("Unsupported settings schema version");
    const invalid = schema.settings.filter(e => Object.prototype.hasOwnProperty.call(doc, e.key) && !valid(e, doc[e.key])).map(e => e.key);
    if (invalid.length) throw new Error("Invalid settings: " + invalid.join(", "));
    return doc;
}
function overrides(doc, active, queue) {
    const result = Object.assign(Object.create(null), doc);
    for (const patch of (active ? [active] : []).concat(queue)) {
        if (patch.reset) delete result[patch.key];
        else result[patch.key] = patch.value;
    }
    return result;
}
function rows(schema) {
    const result = schema.settings.map(e => ({page:e.section, label:e.label, detail:e.detail, group:e.group || "", words:(e.label + " " + e.detail + " " + e.searchTerms).toLowerCase()})).concat(schema.additionalRows || []);
    const seen = new Set();
    return result.filter(r => { const key = JSON.stringify([r.page,r.label,r.group]); if (seen.has(key)) return false; seen.add(key); return true; });
}
