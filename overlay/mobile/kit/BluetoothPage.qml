import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Flickable {
    id: page
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: body.height
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-bluetooth"
    property var radio: ({available: false, devices: []})
    // "power", "scan", or the address of the device an action is working on.
    property string busy: ""
    property string message: ""
    // Paired device whose Connect/Forget actions are open.
    property string selected: ""
    readonly property bool powered: radio.available === true && radio.powered === true
    readonly property var paired: (radio.devices || []).filter(d => d.paired)
    readonly property var nearby: (radio.devices || []).filter(d => !d.paired && d.named)
    function refresh() { if (!probe.running) probe.running = true; }
    // Replacing the model rebuilds every row, so only apply real changes.
    function apply(result) {
        if (JSON.stringify(result) !== JSON.stringify(radio)) radio = result;
    }
    function run(args, busyKey) {
        if (action.running) return;
        busy = busyKey;
        message = "";
        action.command = [helper].concat(args);
        action.running = true;
    }
    function describe(device) {
        if (busy === device.address) return "Working…";
        if (device.connected)
            return device.battery !== null && device.battery !== undefined ? "Connected · " + device.battery + "%" : "Connected";
        return device.paired ? "Not connected" : "Pair";
    }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: [page.helper]
        stdout: StdioCollector {}
        onExited: {
            try { page.apply(JSON.parse(stdout.text)); }
            catch (e) { page.apply({available: false, reason: "Could not read Bluetooth", devices: []}); }
        }
    }
    Process {
        id: action
        stdout: StdioCollector {}
        onExited: {
            try {
                const result = JSON.parse(stdout.text);
                page.message = result.message || "";
                delete result.ok;
                delete result.message;
                page.apply(result);
            } catch (e) {
                page.message = "Bluetooth did not answer.";
            }
            page.busy = "";
        }
    }
    // Connections change underneath the page, and scan results arrive over time.
    Timer {
        interval: page.busy === "scan" ? 1500 : 4000
        repeat: true
        running: page.visible
        onTriggered: page.refresh()
    }
    Column {
        id: body
        width: page.width
        spacing: 12
        Text {
            width: parent.width
            text: page.busy === "power" ? (page.powered ? "Turning off…" : "Turning on…")
                : page.powered ? "On" : page.radio.available || page.radio.startable ? "Off" : "Unavailable"
            color: MobileTheme.accent
            font.family: MobileTheme.fontFamily
            font.pixelSize: 48
            font.bold: true
        }
        SettingsRow {
            width: parent.width
            label: "Bluetooth"
            value: page.powered ? "On" : "Off"
            selected: page.powered
            enabled: (page.radio.available === true || page.radio.startable === true) && !action.running
            onClicked: page.run(["power", page.powered ? "off" : "on"], "power")
        }
        DetailRow { width: parent.width; visible: page.radio.available === true; label: "Visible as"; value: page.radio.name || "—" }
        Text {
            visible: page.powered && page.paired.length > 0
            width: parent.width
            text: "Paired devices"
            color: MobileTheme.foreground
            font.family: MobileTheme.fontFamily
            font.pixelSize: 16
            font.bold: true
            topPadding: 8
        }
        Repeater {
            model: page.powered ? page.paired : []
            delegate: Column {
                required property var modelData
                width: body.width
                spacing: 8
                SettingsRow {
                    width: parent.width
                    label: modelData.name
                    value: page.describe(modelData)
                    selected: modelData.connected
                    enabled: !action.running
                    onClicked: page.selected = page.selected === modelData.address ? "" : modelData.address
                }
                Row {
                    visible: page.selected === modelData.address
                    width: parent.width
                    spacing: 10
                    TouchButton {
                        width: (parent.width - 10) / 2
                        label: modelData.connected ? "Disconnect" : "Connect"
                        enabled: !action.running
                        onClicked: page.run([modelData.connected ? "disconnect" : "connect", modelData.address], modelData.address)
                    }
                    TouchButton {
                        width: (parent.width - 10) / 2
                        label: "Forget"
                        enabled: !action.running
                        onClicked: {
                            page.selected = "";
                            page.run(["forget", modelData.address], modelData.address);
                        }
                    }
                }
            }
        }
        Text {
            visible: page.powered && (page.nearby.length > 0 || page.busy === "scan")
            width: parent.width
            text: "Available devices"
            color: MobileTheme.foreground
            font.family: MobileTheme.fontFamily
            font.pixelSize: 16
            font.bold: true
            topPadding: 8
        }
        Repeater {
            model: page.powered ? page.nearby : []
            delegate: SettingsRow {
                required property var modelData
                width: body.width
                label: modelData.name
                value: page.describe(modelData)
                enabled: !action.running
                onClicked: page.run(["pair", modelData.address], modelData.address)
            }
        }
        TouchButton {
            width: parent.width
            label: page.busy === "scan" ? "Scanning…" : "Scan for devices"
            enabled: page.powered && !action.running
            onClicked: page.run(["scan", "15"], "scan")
        }
        Text {
            width: parent.width
            visible: page.message.length > 0
            wrapMode: Text.WordWrap
            text: page.message
            color: MobileTheme.foreground
            font.family: MobileTheme.fontFamily
            font.pixelSize: 14
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            topPadding: 8
            text: page.radio.available || page.radio.startable
                ? "Put a device in pairing mode, scan, then tap it. Headphones, speakers, mice and game controllers pair directly; keyboards that ask for a PIN are not supported yet."
                : page.radio.reason || "Bluetooth is not available."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 14
        }
    }
}
