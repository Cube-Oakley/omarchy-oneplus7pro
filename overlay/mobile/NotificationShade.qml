import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications

PanelWindow {
    id: shade
    property string detail: ""
    property bool screenshotPrivacy: false
    property real topInset: 36
    property bool keyboardOwned: false
    property string editingField: ""
    property var selectedNetwork: null
    property var networks: []
    property string networkMessage: ""
    property var weather: ({configured: false})
    property var locations: []
    property string weatherMessage: ""
    property string pendingInput: ""
    property string weatherInput: ""
    property date month: new Date()
    readonly property bool opened: motion.progress > 0
    readonly property var battery: MobileStatus.battery
    readonly property var wifi: MobileStatus.wifi
    readonly property int notificationCount: notifications.trackedNotifications.values.length
    signal opening()
    signal keyboardRequested(string action)
    anchors { top: true; left: true; right: true; bottom: true }
    // Keyboard exclusive-zone changes must not resize the shade behind menus.
    margins.top: topInset
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"
    visible: true
    mask: Region { width: shade.opened || motion.dragging ? shade.width : 0; height: shade.opened || motion.dragging ? shade.height : 0 }
    WlrLayershell.namespace: "omarchy-mobile-shade"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: editingField !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    function amount(value, unit, decimals) { return value === null || value === undefined ? "—" : Number(value).toFixed(decimals || 0) + " " + unit; }
    function begin() { opening(); motion.begin(); MobileStatus.refresh(); }
    function move(distance, velocity) { motion.update(distance, velocity); }
    function release() { motion.finish(); }
    function cancel() { motion.cancel(); }
    function open() { opening(); motion.animateTo(1); MobileStatus.refresh(); fetchWeather("status", {}); }
    function close() { closeDetail(); motion.animateTo(0); }
    function toggle() { if (opened) close(); else open(); }
    function releaseKeyboard() {
        editingField = "";
        password.focus = false; locationInput.focus = false;
        if (keyboardOwned) keyboardRequested("hide");
        keyboardOwned = false;
    }
    function editField(name, field) {
        editingField = name;
        field.forceActiveFocus(Qt.MouseFocusReason);
        keyboardOwned = true;
        keyboardRequested("show");
    }
    function closeDetail() { releaseKeyboard(); detail = ""; selectedNetwork = null; password.text = ""; }
    function showDetail(name) {
        if (screenshotPrivacy && (name === "wifi" || name === "weather")) return;
        if (!opened) open();
        closeDetail(); detail = name;
        if (name === "wifi") networkAction("scan", {});
        if (name === "weather") fetchWeather("status", {});
        if (name === "calendar") month = new Date(clock.date.getFullYear(), clock.date.getMonth(), 1);
    }
    function networkAction(action, values) {
        if (networkProcess.running || !wifi.interface) return;
        values.interface = wifi.interface;
        pendingInput = JSON.stringify(values) + "\n";
        networkProcess.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-wifi", action];
        networkMessage = action === "scan" ? "Looking for nearby networks…" : action === "connect" ? "Connecting…" : "Updating…";
        networkProcess.running = true;
    }
    function fetchWeather(action, values) {
        if (weatherProcess.running) return;
        weatherInput = JSON.stringify(values) + "\n";
        weatherProcess.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-weather", action];
        weatherMessage = "Updating…";
        weatherProcess.running = true;
    }
    function weatherName(code) {
        if (code === 0) return "Clear skies";
        if (code <= 3) return "Cloudy";
        if (code <= 48) return "Fog";
        if (code <= 67) return "Rain";
        if (code <= 77) return "Snow";
        if (code <= 82) return "Showers";
        if (code <= 86) return "Snow showers";
        return "Thunderstorms";
    }
    DrawerMotion {
        id: motion; travel: sheet.height
        onClosed: shade.closeDetail()
        onSettledOpenChanged: if (settledOpen) shade.fetchWeather("status", {})
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Timer { interval: 5000; repeat: true; running: shade.opened; onTriggered: MobileStatus.refresh() }
    Process {
        id: networkProcess; stdinEnabled: true
        stdout: StdioCollector {}
        onStarted: { write(shade.pendingInput); shade.pendingInput = ""; stdinEnabled = false; }
        onExited: (code, status) => {
            stdinEnabled = true;
            try {
                const result = JSON.parse(stdout.text);
                shade.networkMessage = result.ok ? "" : result.error || "Network request failed";
                if (result.networks) shade.networks = result.networks;
                else if (result.ok) { shade.selectedNetwork = null; password.text = ""; if (shade.detail === "wifi") shade.releaseKeyboard(); }
            } catch (e) { shade.networkMessage = "Network request failed"; }
            MobileStatus.refresh();
        }
    }
    Process {
        id: weatherProcess; stdinEnabled: true
        stdout: StdioCollector {}
        onStarted: { write(shade.weatherInput); shade.weatherInput = ""; stdinEnabled = false; }
        onExited: (code, status) => {
            stdinEnabled = true;
            try {
                const result = JSON.parse(stdout.text);
                shade.weatherMessage = result.error || "";
                if (result.locations) {
                    shade.locations = result.locations;
                    if (!result.locations.length) shade.weatherMessage = result.error || "No matching locations";
                } else if (result.configured !== undefined) {
                    shade.weather = result;
                    shade.locations = [];
                }
            } catch (e) { shade.weatherMessage = "Weather unavailable"; }
        }
    }
    NotificationServer {
        id: notifications
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        persistenceSupported: true
        onNotification: notification => {
            notification.tracked = true;
            // Bound session history; old cards are explicitly dismissed.
            const all = trackedNotifications.values;
            if (all.length > 100) all[0].dismiss();
        }
    }
    Rectangle {
        anchors.fill: parent; color: "black"; opacity: motion.progress * 0.4
        MouseArea { anchors.fill: parent; onClicked: shade.close() }
    }
    Rectangle {
        id: sheet
        width: parent.width; height: parent.height
        y: -height * (1 - motion.progress)
        radius: motion.progress < 0.999 ? 28 : 0; color: MobileTheme.background
        border.color: MobileTheme.muted; border.width: 1
        clip: true
        MouseArea { anchors.fill: parent; onClicked: {} }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 22; spacing: 16
            Item {
                Layout.fillWidth: true; implicitHeight: 72
                Text { font.family: MobileTheme.fontFamily; y: 0; text: Qt.formatDateTime(clock.date, "dddd, MMMM d").toUpperCase(); color: MobileTheme.accent; font.pixelSize: 11; font.letterSpacing: 1.5 }
                Text { font.family: MobileTheme.fontFamily; y: 24; text: "At a glance"; color: MobileTheme.foreground; font.pixelSize: 32; font.bold: true }
                TouchButton { anchors.right: parent.right; y: 19; implicitWidth: 46; implicitHeight: 46; label: "⌃"; onClicked: shade.close() }
            }
            GridLayout {
                Layout.fillWidth: true; columns: 2; columnSpacing: 12; rowSpacing: 12
                ShadeTile {
                    Layout.fillWidth: true; Layout.preferredWidth: 1
                    symbol: "⌁"; title: !shade.screenshotPrivacy && shade.wifi.connected ? shade.wifi.ssid || shade.wifi.connection : "Wi-Fi"
                    subtitle: shade.wifi.connected ? "Connected · " + shade.amount(shade.wifi.signal, "%") : "Choose a network"
                    highlight: shade.wifi.connected === true; onClicked: shade.showDetail("wifi")
                }
                ShadeTile {
                    Layout.fillWidth: true; Layout.preferredWidth: 1
                    symbol: shade.battery.charging ? "ϟ" : "▯"; title: shade.amount(shade.battery.capacity, "%")
                    subtitle: shade.amount(shade.battery.charge_mah, "mAh") + " · " + shade.amount(shade.battery.current_ma, "mA")
                    onClicked: shade.showDetail("battery")
                }
                ShadeTile {
                    Layout.fillWidth: true; Layout.preferredWidth: 1
                    symbol: "◷"; title: Qt.formatDateTime(clock.date, "h:mm AP")
                    subtitle: Qt.formatDateTime(clock.date, "MMM d, yyyy") + " · Calendar"; onClicked: shade.showDetail("calendar")
                }
                ShadeTile {
                    Layout.fillWidth: true; Layout.preferredWidth: 1
                    symbol: "☀"; title: shade.weather.available ? shade.amount(shade.weather.current.temperature_2m, "°F") : "Weather"
                    subtitle: shade.weather.available ? shade.weatherName(shade.weather.current.weather_code) + (shade.weather.stale ? " · Offline" : "") : "Choose your location"
                    onClicked: shade.showDetail("weather")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { font.family: MobileTheme.fontFamily; text: "Notifications"; color: MobileTheme.foreground; font.pixelSize: 19; font.bold: true; Layout.fillWidth: true }
                TouchButton {
                    visible: !shade.screenshotPrivacy && shade.notificationCount > 0; implicitWidth: 90; implicitHeight: 42; label: "Clear all"; textSize: 13
                    onClicked: notifications.trackedNotifications.values.slice().forEach(n => n.dismiss())
                }
            }
            ListView {
                id: notices
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; spacing: 10
                model: shade.screenshotPrivacy ? [] : notifications.trackedNotifications.values.slice().reverse()
                boundsBehavior: Flickable.StopAtBounds
                Text { font.family: MobileTheme.fontFamily; anchors.centerIn: parent; visible: shade.screenshotPrivacy || shade.notificationCount === 0; text: shade.screenshotPrivacy ? "Notification contents hidden\nfor this screenshot." : "All caught up\nYour notifications will appear here."; horizontalAlignment: Text.AlignHCenter; color: MobileTheme.secondary; font.pixelSize: 15; lineHeight: 1.5 }
                delegate: Rectangle {
                    required property var modelData
                    width: notices.width; height: noticeContent.implicitHeight + 30; radius: 18; color: MobileTheme.surface
                    ColumnLayout {
                        id: noticeContent; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 15 } spacing: 8
                        RowLayout {
                            Text { font.family: MobileTheme.fontFamily; text: modelData.appName || "Notification"; textFormat: Text.PlainText; color: MobileTheme.accent; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                            TouchButton { implicitWidth: 40; implicitHeight: 40; label: "×"; onClicked: modelData.dismiss() }
                        }
                        Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: modelData.summary; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: MobileTheme.foreground; font.bold: true; font.pixelSize: 16 }
                        Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: modelData.body; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight; color: MobileTheme.secondary; font.pixelSize: 14; visible: text.length > 0 }
                        Flow {
                            Layout.fillWidth: true; spacing: 8
                            Repeater {
                                model: modelData.actions
                                TouchButton { required property var modelData; implicitWidth: 130; implicitHeight: 44; label: modelData.text; textSize: 13; onClicked: modelData.invoke() }
                            }
                        }
                    }
                }
            }
            Item {
                Layout.fillWidth: true; implicitHeight: 22
                Rectangle { anchors.centerIn: parent; width: 64; height: 4; radius: 2; color: MobileTheme.secondary; opacity: 0 }
            }
        }
        DrawerPull {
            anchors.fill: parent
            directionSign: -1
            available: shade.detail === "" && motion.progress > 0.05 && !motion.dragging
            atTop: notices.atYEnd || notices.contentHeight <= notices.height
            headerBottom: notices.y + 22
            blocked: shade.detail !== ""
            onStarted: motion.begin()
            onMoved: (distance, velocity) => motion.update(Math.min(0, distance), velocity)
            onReleased: motion.finishClose()
            onCanceled: if (motion.dragging) motion.cancel()
        }
    }
    Rectangle {
        anchors.fill: parent; visible: shade.detail !== ""; color: "#88000000"
        MouseArea { anchors.fill: parent; onClicked: shade.closeDetail() }
    }
    Rectangle {
        id: popup
        visible: shade.detail !== ""
        width: parent.width - 32
        height: Math.min(popupContent.implicitHeight + 44, parent.height - (shade.keyboardOwned ? ((MobileTheme.state.device || {}).keyboardHeight || 280) + 48 : 48))
        anchors.horizontalCenter: parent.horizontalCenter
        y: shade.selectedNetwork || locationInput.activeFocus ? 24 : Math.max(24, (parent.height - height) / 2 - 30)
        color: MobileTheme.background; radius: 26; border.width: 1; border.color: MobileTheme.accent
        MouseArea { anchors.fill: parent; onClicked: {} }
        Flickable {
            anchors.fill: parent; anchors.margins: 22; clip: true
            contentHeight: popupContent.implicitHeight; boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: popupContent; width: parent.width; spacing: 16
                RowLayout {
                    Layout.fillWidth: true
                    Text { font.family: MobileTheme.fontFamily; text: shade.detail === "wifi" ? "Wi-Fi" : shade.detail === "battery" ? "Battery" : shade.detail === "calendar" ? "Calendar" : "Weather"; color: MobileTheme.foreground; font.pixelSize: 26; font.bold: true; Layout.fillWidth: true }
                    TouchButton { implicitWidth: 44; implicitHeight: 44; label: "×"; onClicked: shade.closeDetail() }
                }
                ColumnLayout {
                    visible: shade.detail === "battery"; Layout.fillWidth: true; spacing: 15
                    Text { font.family: MobileTheme.fontFamily; text: shade.amount(shade.battery.capacity, "%"); color: MobileTheme.accent; font.pixelSize: 48; font.bold: true }
                    DetailRow { Layout.fillWidth: true; label: "Battery status"; value: shade.battery.status || "Unavailable" }
                    DetailRow { Layout.fillWidth: true; label: "Stored charge"; value: shade.amount(shade.battery.charge_mah, "mAh") }
                    DetailRow { Layout.fillWidth: true; label: "Reported full"; value: shade.amount(shade.battery.full_mah, "mAh") }
                    DetailRow { Layout.fillWidth: true; label: "Design capacity"; value: shade.amount(shade.battery.design_mah, "mAh") }
                    DetailRow { Layout.fillWidth: true; label: "Net current"; value: shade.amount(shade.battery.current_ma, "mA") }
                    DetailRow { Layout.fillWidth: true; label: "Voltage"; value: shade.amount(shade.battery.voltage_v, "V", 3) }
                    DetailRow { Layout.fillWidth: true; label: "Temperature"; value: shade.amount(shade.battery.temperature_c, "°C", 1) }
                    Repeater {
                        model: shade.battery.chargers || []
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true; spacing: 15
                            DetailRow { Layout.fillWidth: true; label: "Charger"; value: modelData.status }
                            DetailRow { Layout.fillWidth: true; label: "USB input limit"; value: shade.amount(modelData.input_limit_ma, "mA") }
                        }
                    }
                    Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: "Net current is what enters (+) or leaves (−) the battery. The USB input limit is a configured ceiling, not measured charge current. Battery and charger report their states independently."; wrapMode: Text.WordWrap; color: MobileTheme.secondary; font.pixelSize: 12 }
                }
                ColumnLayout {
                    visible: shade.detail === "wifi"; Layout.fillWidth: true; spacing: 12
                    Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: shade.wifi.connected ? shade.wifi.ssid || shade.wifi.connection : "Not connected"; textFormat: Text.PlainText; color: MobileTheme.accent; font.pixelSize: 20; elide: Text.ElideRight }
                    DetailRow { Layout.fillWidth: true; label: "IPv4"; value: (shade.wifi.ipv4 || []).join("\n") || "—" }
                    DetailRow { Layout.fillWidth: true; label: "IPv6"; value: (shade.wifi.ipv6 || []).join("\n") || "—" }
                    DetailRow { Layout.fillWidth: true; label: "Gateway"; value: shade.wifi.gateway || "—" }
                    DetailRow { Layout.fillWidth: true; label: "DNS servers"; value: (shade.wifi.dns || []).join("\n") || "—" }
                    RowLayout {
                        Layout.fillWidth: true
                        TouchButton { Layout.fillWidth: true; label: "Refresh"; enabled: !networkProcess.running; onClicked: shade.networkAction("scan", {}) }
                        TouchButton { Layout.fillWidth: true; label: "Disconnect"; enabled: shade.wifi.connected === true && !networkProcess.running; onClicked: shade.networkAction("disconnect", {}) }
                    }
                    Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; visible: shade.networkMessage.length > 0; text: shade.networkMessage; wrapMode: Text.WordWrap; color: MobileTheme.secondary; font.pixelSize: 13 }
                    ColumnLayout {
                        visible: shade.selectedNetwork !== null; Layout.fillWidth: true; spacing: 10
                        Text { font.family: MobileTheme.fontFamily; text: shade.selectedNetwork ? shade.selectedNetwork.ssid : ""; textFormat: Text.PlainText; color: MobileTheme.foreground; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                        TouchTextField { font.family: MobileTheme.fontFamily;
                            id: password; Layout.fillWidth: true; implicitHeight: 50
                            placeholderText: "Password (blank uses a saved connection)"; echoMode: TextInput.Password
                            color: MobileTheme.foreground; placeholderTextColor: MobileTheme.secondary
                            background: Rectangle { radius: 10; color: MobileTheme.surface; border.color: MobileTheme.muted }
                            editing: shade.editingField === "password" && shade.detail === "wifi"
                            onEditingRequested: shade.editField("password", password)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            TouchButton { Layout.fillWidth: true; label: "Connect"; enabled: !networkProcess.running; selected: true; onClicked: { shade.networkAction("connect", {bssid: shade.selectedNetwork.bssid, password: password.text}); password.text = ""; shade.releaseKeyboard(); } }
                            TouchButton { Layout.fillWidth: true; label: "Cancel"; onClicked: { shade.selectedNetwork = null; password.text = ""; if (shade.detail === "wifi") shade.releaseKeyboard(); } }
                        }
                    }
                    Repeater {
                        model: shade.selectedNetwork ? [] : shade.networks
                        TouchButton {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 62; textSize: 14
                            label: (modelData.active ? "✓  " : "") + modelData.ssid + "   ·   " + modelData.signal + "%  " + modelData.security
                            selected: modelData.active; enabled: !networkProcess.running
                            onClicked: {
                                if (/802\.1X|EAP|WEP/.test(modelData.security)) { shade.networkMessage = "This security type needs an advanced NetworkManager profile."; return; }
                                shade.selectedNetwork = modelData; password.text = "";
                            }
                        }
                    }
                }
                ColumnLayout {
                    visible: shade.detail === "calendar"; Layout.fillWidth: true; spacing: 16
                    RowLayout {
                        Layout.fillWidth: true
                        TouchButton { implicitWidth: 44; implicitHeight: 44; label: "‹"; onClicked: shade.month = new Date(shade.month.getFullYear(), shade.month.getMonth() - 1, 1) }
                        Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: Qt.formatDateTime(shade.month, "MMMM yyyy"); color: MobileTheme.accent; font.pixelSize: 18 }
                        TouchButton { implicitWidth: 44; implicitHeight: 44; label: "›"; onClicked: shade.month = new Date(shade.month.getFullYear(), shade.month.getMonth() + 1, 1) }
                    }
                    GridLayout {
                        Layout.fillWidth: true; columns: 7; columnSpacing: 3; rowSpacing: 7
                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            Text { font.family: MobileTheme.fontFamily; required property string modelData; text: modelData; Layout.fillWidth: true; Layout.preferredWidth: 1; horizontalAlignment: Text.AlignHCenter; color: MobileTheme.secondary; font.pixelSize: 13 }
                        }
                        Repeater {
                            model: 42
                            Rectangle {
                                required property int index
                                readonly property date day: new Date(shade.month.getFullYear(), shade.month.getMonth(), index - new Date(shade.month.getFullYear(), shade.month.getMonth(), 1).getDay() + 1)
                                readonly property bool today: Qt.formatDateTime(day, "yyyy-MM-dd") === Qt.formatDateTime(clock.date, "yyyy-MM-dd")
                                Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 39; radius: 12
                                color: today ? MobileTheme.accent : "transparent"
                                Text { font.family: MobileTheme.fontFamily; anchors.centerIn: parent; text: parent.day.getDate(); color: parent.today ? MobileTheme.background : MobileTheme.foreground; opacity: parent.day.getMonth() === shade.month.getMonth() ? 1 : 0.3; font.pixelSize: 15 }
                            }
                        }
                    }
                    TouchButton { Layout.fillWidth: true; label: "Today"; onClicked: shade.month = new Date(clock.date.getFullYear(), clock.date.getMonth(), 1) }
                }
                ColumnLayout {
                    visible: shade.detail === "weather"; Layout.fillWidth: true; spacing: 12
                    Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: shade.weather.location ? shade.weather.location.name : "Choose a location"; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: MobileTheme.accent; font.pixelSize: 17 }
                    Text { font.family: MobileTheme.fontFamily; visible: shade.weather.available === true; text: shade.weather.available ? shade.amount(shade.weather.current.temperature_2m, "°F") + " · " + shade.weatherName(shade.weather.current.weather_code) : ""; color: MobileTheme.foreground; font.pixelSize: 25; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    DetailRow { visible: shade.weather.available === true; Layout.fillWidth: true; label: "Feels like"; value: shade.weather.available ? shade.amount(shade.weather.current.apparent_temperature, "°F") : "—" }
                    DetailRow { visible: shade.weather.available === true; Layout.fillWidth: true; label: "Wind"; value: shade.weather.available ? shade.amount(shade.weather.current.wind_speed_10m, "mph") : "—" }
                    Repeater {
                        model: shade.weather.available ? shade.weather.daily.time : []
                        DetailRow { required property string modelData; required property int index; Layout.fillWidth: true; label: modelData; value: shade.amount(shade.weather.daily.temperature_2m_min[index], "°") + " / " + shade.amount(shade.weather.daily.temperature_2m_max[index], "°F") }
                    }
                    Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: shade.weatherMessage; visible: text.length > 0; wrapMode: Text.WordWrap; color: MobileTheme.secondary; font.pixelSize: 13 }
                    TouchTextField { font.family: MobileTheme.fontFamily;
                        id: locationInput; Layout.fillWidth: true; implicitHeight: 50; placeholderText: "City or postal code"
                        color: MobileTheme.foreground; placeholderTextColor: MobileTheme.secondary
                        background: Rectangle { radius: 10; color: MobileTheme.surface; border.color: MobileTheme.muted }
                        editing: shade.editingField === "location" && shade.detail === "weather"
                        onEditingRequested: shade.editField("location", locationInput)
                    }
                    TouchButton { Layout.fillWidth: true; label: "Find location"; enabled: !weatherProcess.running; onClicked: { shade.fetchWeather("search", {query: locationInput.text}); shade.releaseKeyboard(); } }
                    Repeater {
                        model: shade.locations
                        TouchButton { required property var modelData; Layout.fillWidth: true; label: modelData.name; textSize: 13; onClicked: shade.fetchWeather("set", modelData) }
                    }
                    Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: "Weather data: Open-Meteo · CC BY 4.0\nManual location · updates at most every 15 minutes"; wrapMode: Text.WordWrap; color: MobileTheme.secondary; font.pixelSize: 11 }
                }
            }
        }
    }
}
