import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The shell writes a new stamp when the left-edge gesture commits.
// Whichever app window is on screen consumes it. Header back buttons
// stay in the app; this is the same signal.
Item {
    id: watch
    property string windowTitle: ""
    property string ownPid: ""
    signal back()
    property string stamp: ""
    property bool ready: false
    function focused() {
        const tops = Hyprland.toplevels.values;
        for (let i = 0; i < tops.length; i++) {
            const window = tops[i];
            if (!window.workspace || window.workspace.id !== 1) continue;
            const info = window.lastIpcObject || {};
            const pid = info.pid ? String(info.pid) : "";
            if (watch.ownPid && pid === watch.ownPid) return true;
            const title = info.title ? info.title : (window.title || "");
            if (watch.windowTitle && title === watch.windowTitle) return true;
        }
        return false;
    }
    Process {
        id: who
        command: ["sh", "-c", "echo $PPID"]
        stdout: StdioCollector {}
        running: true
        onExited: watch.ownPid = stdout.text.trim()
    }
    Process {
        id: read
        command: ["cat", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-mobile/back"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: {
            const text = stdout.text.trim();
            if (!watch.ready) {
                watch.stamp = text;
                watch.ready = true;
                return;
            }
            if (!text || text === watch.stamp) return;
            watch.stamp = text;
            if (watch.focused()) watch.back();
        }
    }
    Timer {
        interval: 160
        repeat: true
        running: true
        onTriggered: if (!read.running) read.running = true
    }
}
