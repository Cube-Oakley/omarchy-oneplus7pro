import Quickshell
import Quickshell.Io

ShellRoot {
    Process {
        command: ["/usr/bin/env", "WAYLAND_DISPLAY=wayland-1", "XDG_RUNTIME_DIR=/run/user/0",
                  "/root/.local/bin/omarchy-mobile-session", "launch"]
        running: true
        onExited: (code, status) => { if (code === 0) Qt.quit(); else console.error("Mobile session failed to start"); }
    }
}
