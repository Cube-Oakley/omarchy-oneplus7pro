import QtQuick

// AOSP/Lineage electron-beam curve. Off: squash to a line, then that line
// collapses to the center. On: the line grows from the center, then opens.
QtObject {
    function sample(mode, t) {
        const x = Math.max(0, Math.min(1, t));
        const line = 0.004;
        if (mode === "on") {
            if (x < 0.36) {
                const u = x / 0.36;
                const e = 1 - Math.pow(1 - u, 3);
                return {stretch: line, collapse: e, beam: 1 - u * 0.2};
            }
            const u = (x - 0.36) / 0.64;
            const e = 1 - Math.pow(1 - u, 3);
            return {stretch: line + (1 - line) * e, collapse: 1, beam: (1 - u) * 0.8};
        }
        if (x < 0.65) {
            const u = x / 0.65;
            const e = u * u * u;
            return {stretch: 1 - (1 - line) * e, collapse: 1, beam: Math.min(1, e * 1.6)};
        }
        const u = (x - 0.65) / 0.35;
        const e = u * u;
        return {stretch: line, collapse: 1 - e, beam: 1 - u * 0.15};
    }
}
