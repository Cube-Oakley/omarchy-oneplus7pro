import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The always-on display (Settings → Display): in place of switching the panel
// off, a black screen with the time, date, battery and the apps that have
// notifications, dim. Black OLED pixels are off, and a command-mode panel
// keeps showing its last frame, so this redraws once a minute: the clock, and
// a small shift of everything against burn-in. The power button or a double
// tap wakes the phone (omarchy-mobile-display on). It fades in on the black
// the CRT close leaves and out onto it before the CRT opens; face down or in a
// pocket the panel goes fully off under it (omarchy-mobile-ambient).
PanelWindow {
    id: ambient
    // The shade's notifications (NotificationServer.trackedNotifications).
    property var notifications: []
    readonly property var apps: {
        const seen = {};
        const list = [];
        for (const item of notifications) {
            const key = item.appName || "Notification";
            if (seen[key]) continue;
            seen[key] = true;
            list.push({name: key, icon: item.appIcon || ""});
        }
        return list.slice(0, 6);
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    property real level: MobileStatus.ambient ? 1 : 0
    Behavior on level { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
    visible: level > 0
    Rectangle { anchors.fill: parent; color: "black"; opacity: ambient.level }
    WlrLayershell.namespace: "omarchy-mobile-ambient"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    SystemClock { id: clock; precision: SystemClock.Minutes }
    // Burn-in: a new spot every minute, a few pixels from the last, within
    // a small box around the middle of the upper half.
    property real shiftX: 0
    property real shiftY: 0
    Connections {
        target: clock
        function onDateChanged() {
            ambient.shiftX = Math.max(-24, Math.min(24, ambient.shiftX + (Math.random() * 16 - 8)));
            ambient.shiftY = Math.max(-40, Math.min(40, ambient.shiftY + (Math.random() * 16 - 8)));
        }
    }

    // Face down or in a pocket, the panel goes off under the clock.
    Connections {
        target: MobileStatus
        function onAmbientChanged() { pocket.running = MobileStatus.ambient; }
    }
    Process {
        id: pocket
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-ambient", "watch"]
        onExited: if (MobileStatus.ambient) pocketRetry.start()
    }
    Timer { id: pocketRetry; interval: 5000; onTriggered: pocket.running = MobileStatus.ambient }

    Column {
        opacity: ambient.level
        x: (ambient.width - width) / 2 + ambient.shiftX
        y: ambient.height * 0.22 + ambient.shiftY
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: MobileTheme.foreground
            opacity: 0.9
            font.family: MobileTheme.fontFamily
            font.pixelSize: 84
            font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 17
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property var battery: MobileStatus.battery || ({})
            visible: battery.capacity !== undefined
            text: (battery.charging ? "ϟ " : "") + battery.capacity + "%"
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 15
        }
        Item { width: 1; height: 18 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14
            visible: ambient.apps.length > 0
            Repeater {
                model: ambient.apps
                Item {
                    required property var modelData
                    width: 26; height: 26
                    Image {
                        id: icon
                        anchors.fill: parent
                        source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                        sourceSize: Qt.size(26, 26)
                        opacity: 0.8
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: icon.status !== Image.Ready
                        text: modelData.name.substring(0, 1)
                        color: MobileTheme.secondary
                        font.family: MobileTheme.fontFamily
                        font.pixelSize: 17
                        font.bold: true
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: ambient.notifications.length > 0
            text: ambient.notifications.length === 1 ? "1 notification" : ambient.notifications.length + " notifications"
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 13
        }
    }

    // Touches stop here: nothing behind reacts. A double tap wakes the phone.
    Item {
        anchors.fill: parent
        TapHandler {
            onDoubleTapped: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-display", "on"])
        }
    }
}
