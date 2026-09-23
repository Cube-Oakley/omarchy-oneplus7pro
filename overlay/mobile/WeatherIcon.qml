pragma Singleton
import QtQuick

QtObject {
    function glyph(kind) {
        return {
            clear: "󰖙",
            mostly_clear: "󰖕",
            cloudy: "󰖐",
            fog: "󰖑",
            drizzle: "󰖗",
            rain: "󰖖",
            snow: "󰖘",
            showers: "󰖒",
            thunder: "󰖓",
            unknown: "󰖐"
        }[kind] || "󰖐";
    }
}
