pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
    id: status
    property alias battery: batteryProbe.state
    property alias wifi: wifiProbe.state
    property alias bluetooth: bluetoothProbe.state
    property alias volume: volumeProbe.state
    property alias stats: statsProbe.state
    property bool dnd: false
    // Set while the shade's performance page is open.
    property bool statsShown: false
    // Busy share of all CPUs and used memory, in percent, for the status bar.
    property var cpuPercent: null
    property var memoryPercent: null
    function refresh() {
        batteryProbe.refresh(); wifiProbe.refresh(); bluetoothProbe.refresh();
        volumeProbe.refresh(); statsProbe.refresh();
    }
    function setDnd(enabled) {
        dnd = enabled;
        prefsInput = JSON.stringify({dnd: enabled}) + "\n";
        prefsSave.running = true;
    }
    property string prefsInput: ""
    StatusProbe {
        id: batteryProbe
        sampleCommand: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-battery"]
        eventCommand: ["env", "SYSTEMD_IN_CHROOT=0", "stdbuf", "-oL", "udevadm", "monitor", "--kernel", "--subsystem-match=power_supply"]
    }
    StatusProbe {
        id: wifiProbe
        sampleCommand: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-wifi"]
        eventCommand: ["stdbuf", "-oL", "nmcli", "monitor"]
        pollInterval: 30000
    }
    StatusProbe {
        id: bluetoothProbe
        sampleCommand: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-bluetooth"]
        // BlueZ signals power, connection and pairing changes on the system bus.
        eventCommand: ["dbus-monitor", "--system", "type='signal',sender='org.bluez'"]
        pollInterval: 30000
    }
    StatusProbe {
        id: volumeProbe
        sampleCommand: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-volume"]
        pollInterval: 10000
    }
    StatusProbe {
        id: statsProbe
        sampleCommand: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-stats"]
        pollInterval: 3000
        // The full snapshot costs 0.1 CPU-s of Python, and every new result
        // stalled the shell's animations for 60 ms, so it only runs while
        // its page is shown.
        active: status.statsShown
    }
    // The status bar's bars read /proc directly: no process, no stall.
    property var cpuLast: null
    FileView {
        id: procStat
        path: "/proc/stat"
        onLoaded: {
            const line = text().split("\n")[0].split(/\s+/);
            if (line[0] !== "cpu") return;
            const nums = line.slice(1).map(Number);
            const now = {total: nums.reduce((sum, value) => sum + value, 0), idle: nums[3] + (nums[4] || 0)};
            const last = status.cpuLast;
            status.cpuLast = now;
            if (!last || now.total <= last.total) return;
            const busy = 1 - (now.idle - last.idle) / (now.total - last.total);
            status.cpuPercent = Math.round(Math.max(0, Math.min(1, busy)) * 1000) / 10;
        }
    }
    FileView {
        id: procMeminfo
        path: "/proc/meminfo"
        onLoaded: {
            const total = /MemTotal:\s+(\d+)/.exec(text());
            const available = /MemAvailable:\s+(\d+)/.exec(text());
            if (!total || !available) return;
            status.memoryPercent = Math.round(1000 * (1 - Number(available[1]) / Number(total[1]))) / 10;
        }
    }
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: { procStat.reload(); procMeminfo.reload(); }
    }
    Process {
        id: prefsLoad
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-prefs"]
        running: true
        stdout: StdioCollector {}
        onExited: {
            try { status.dnd = JSON.parse(stdout.text).dnd === true; }
            catch (e) { status.dnd = false; }
        }
    }
    Process {
        id: prefsSave
        stdinEnabled: true
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-prefs", "set"]
        stdout: StdioCollector {}
        onStarted: { write(status.prefsInput); status.prefsInput = ""; stdinEnabled = false; }
        onExited: {
            stdinEnabled = true;
            try { status.dnd = JSON.parse(stdout.text).dnd === true; }
            catch (e) {}
        }
    }
}
