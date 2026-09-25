import QtQuick
import Quickshell
import Quickshell.Io

Flickable {
    id: page
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: body.height
    property var screen: ({monitors: [], brightness: false})
    // The always-on display (prefs alwaysOn): the power button shows a dim
    // clock instead of switching the panel off.
    property bool alwaysOn: false
    function refresh() {
        if (!probe.running) probe.running = true;
        if (!prefsLoad.running) prefsLoad.running = true;
    }
    function setAlwaysOn(on) {
        alwaysOn = on;
        prefsSave.payload = JSON.stringify({alwaysOn: on}) + "\n";
        prefsSave.running = true;
    }
    Component.onCompleted: refresh()
    Process {
        id: prefsLoad
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-prefs"]
        stdout: StdioCollector {}
        onExited: {
            try { page.alwaysOn = JSON.parse(stdout.text).alwaysOn === true; }
            catch (e) {}
        }
    }
    Process {
        id: prefsSave
        stdinEnabled: true
        property string payload: ""
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-prefs", "set"]
        stdout: StdioCollector {}
        onStarted: { write(prefsSave.payload); prefsSave.payload = ""; stdinEnabled = false; }
        onExited: {
            stdinEnabled = true;
            try { page.alwaysOn = JSON.parse(stdout.text).alwaysOn === true; }
            catch (e) {}
        }
    }
    Process {
        id: probe
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-displayinfo"]
        running: true
        stdout: StdioCollector {}
        onExited: {
            try { page.screen = JSON.parse(stdout.text); }
            catch (e) { page.screen = {monitors: [], brightness: false}; }
        }
    }
    Column {
        id: body
        width: page.width
        spacing: 12
        Repeater {
            model: page.screen.monitors || []
            delegate: Column {
                required property var modelData
                width: body.width
                spacing: 12
                Text {
                    width: parent.width
                    text: modelData.name || "Display"
                    color: MobileTheme.accent
                    font.family: MobileTheme.fontFamily
                    font.pixelSize: 36
                    font.bold: true
                }
                DetailRow {
                    width: parent.width
                    label: "Resolution"
                    value: (modelData.width && modelData.height) ? modelData.width + " × " + modelData.height : "—"
                }
                DetailRow {
                    width: parent.width
                    label: "Refresh"
                    value: modelData.refresh ? Number(modelData.refresh).toFixed(0) + " Hz" : "—"
                }
                DetailRow { width: parent.width; label: "Scale"; value: modelData.scale ? String(modelData.scale) : "—" }
            }
        }
        Text {
            visible: !(page.screen.monitors && page.screen.monitors.length)
            width: parent.width
            text: "Display"
            color: MobileTheme.accent
            font.family: MobileTheme.fontFamily
            font.pixelSize: 36
            font.bold: true
        }
        SettingsRow {
            width: parent.width
            label: "Brightness"
            value: page.screen.brightness && page.screen.backlight ? page.screen.backlight.percent + "%" : "Not available"
            enabled: false
        }
        SettingsRow {
            width: parent.width
            label: "Always-on display"
            value: page.alwaysOn ? "On" : "Off"
            selected: page.alwaysOn
            onClicked: page.setAlwaysOn(!page.alwaysOn)
        }
        SettingsRow {
            width: parent.width
            label: "Corners"
            value: MobileTheme.square ? "Square" : "Round"
            onClicked: page.appearanceRequested()
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            topPadding: 8
            text: page.screen.brightness
                  ? "Brightness is changed from the shade. With the always-on display, the power button shows a dim clock instead of switching the screen off; press it again or double-tap to wake."
                  : "This panel has no backlight control yet, so brightness cannot be changed. Corners are changed in Appearance."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 14
        }
    }
    signal appearanceRequested()
}
