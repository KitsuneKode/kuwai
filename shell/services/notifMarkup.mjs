const KEEP = /&lt;(\/?)(b|i|u|em|strong)&gt;/gi;
const BREAK = /&lt;br\s*\/?&gt;/gi;

/** @param {unknown} t */
export function styledSafe(t) {
    return String(t || "")
        .replace(/<(script|style|iframe|object)\b[\s\S]*?<\/\1>/gi, "")
        .replace(/</g, "&lt;").replace(/>/g, "&gt;")
        .replace(KEEP, "<$1$2>")
        .replace(BREAK, "<br>");
}

/** @param {unknown} t */
export function plainStyled(t) {
    return String(t || "").replace(/<[^>]*>/g, "").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
