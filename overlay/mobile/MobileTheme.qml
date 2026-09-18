pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: palette
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    FileView {
        id: cachedTheme
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-mobile/palette.json"
        blockLoading: true
        printErrors: false
    }
    function initialState() {
        try { return JSON.parse(cachedTheme.text()); }
        catch (e) { return { name: "tokyo-night", colors: {}, themes: [], device: {} }; }
    }
    property var state: initialState()
    readonly property color background: state.colors.background || "#1a1b26"
    readonly property color surface: state.colors.lighter_background || "#24283b"
    readonly property color foreground: state.colors.bright_foreground || "#c0caf5"
    readonly property color secondary: state.colors.foreground || "#a9b1d6"
    readonly property color accent: state.colors.accent || "#7aa2f7"
    readonly property color selection: state.colors.selection || "#292e42"
    readonly property color muted: state.colors.muted || "#414868"
    property string error: ""
    property string wallpaperError: ""
    property var pendingCommand: []
    readonly property bool busy: pendingCommand.length > 0 || (update.running && update.command[1] !== "sync")
    function request(args) {
        const command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-theme"].concat(args);
        if (update.running) pendingCommand = command;
        else { update.command = command; update.running = true; }
    }
    function runPending() {
        if (pendingCommand.length === 0 || update.running) return;
        update.command = pendingCommand;
        pendingCommand = [];
        update.running = true;
    }
    function nextWallpaper() {
        request(["background", "next"]);
    }
    function select(name) {
        request(["set", name]);
    }
    Process {
        id: update
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-theme", "sync"]
        running: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (code, status) => {
            Qt.callLater(palette.runPending);
            if (code !== 0) {
                palette.error = stderr.text.trim() || "Theme could not be loaded";
                console.warn(palette.error);
                return;
            }
            try { palette.state = JSON.parse(stdout.text); palette.error = ""; }
            catch (e) { palette.error = "Theme could not be loaded"; }
        }
    }
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: if (!update.running) { update.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-theme", "sync"]; update.running = true; }
    }
}
