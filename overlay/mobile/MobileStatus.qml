pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property alias battery: batteryProbe.state
    property alias wifi: wifiProbe.state
    function refresh() { batteryProbe.refresh(); wifiProbe.refresh(); }
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
}
