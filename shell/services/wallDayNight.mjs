/** @param {unknown} previous @param {any} value */
export function newBoundary(previous, value) {
    return value && (value.phase === "day" || value.phase === "night")
        && typeof value.boundary === "string"
        && /^[0-9]{4}-[0-9]{2}-[0-9]{2}:(day|night)$/.test(value.boundary)
        && value.boundary.endsWith(":" + value.phase)
        && value.boundary !== previous;
}
