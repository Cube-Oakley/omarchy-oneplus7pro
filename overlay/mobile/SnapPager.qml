import QtQuick

// Which card a horizontal switcher drag should land on. The strip never
// rests between two apps: a short drag returns, a longer drag or a flick
// commits to a card.
Item {
    function target(index, count, offset, step, velocity) {
        const n = Math.max(0, count | 0);
        if (n <= 0) return 0;
        const width = Math.max(1, Math.abs(step));
        const i = Math.max(0, Math.min(n - 1, index | 0));
        const pages = -offset / width;
        let delta = 0;
        if (velocity <= -700) delta = Math.max(1, Math.ceil(pages));
        else if (velocity >= 700) delta = Math.min(-1, Math.floor(pages));
        else if (pages >= 0.22) delta = Math.max(1, Math.round(pages));
        else if (pages <= -0.22) delta = Math.min(-1, Math.round(pages));
        return Math.max(0, Math.min(n - 1, i + delta));
    }
}
