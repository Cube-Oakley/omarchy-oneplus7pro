import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Flickable {
    id: page
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: body.height
    property var battery: ({available: false})
    function amount(value, unit, decimals) {
        return value === null || value === undefined ? "—" : Number(value).toFixed(decimals || 0) + " " + unit;
    }
    function refresh() { if (!probe.running) probe.running = true; }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-battery"]
        running: true
        stdout: StdioCollector {}
        onExited: {
            try { page.battery = JSON.parse(stdout.text); }
            catch (e) { page.battery = {available: false}; }
        }
    }
    Timer { interval: 5000; running: page.visible; repeat: true; onTriggered: page.refresh() }
    Column {
        id: body
        width: page.width
        spacing: 12
        Text {
            width: parent.width
            text: page.amount(page.battery.capacity, "%")
            color: MobileTheme.accent
            font.family: MobileTheme.fontFamily
            font.pixelSize: 48
            font.bold: true
        }
        DetailRow { width: parent.width; label: "Battery status"; value: page.battery.status || "Unavailable" }
        DetailRow { width: parent.width; label: "Stored charge"; value: page.amount(page.battery.charge_mah, "mAh") }
        DetailRow { width: parent.width; label: "Reported full"; value: page.amount(page.battery.full_mah, "mAh") }
        DetailRow { width: parent.width; label: "Design capacity"; value: page.amount(page.battery.design_mah, "mAh") }
        DetailRow { width: parent.width; label: "Net current"; value: page.amount(page.battery.current_ma, "mA") }
        DetailRow { width: parent.width; label: "Voltage"; value: page.amount(page.battery.voltage_v, "V", 3) }
        DetailRow { width: parent.width; label: "Temperature"; value: page.amount(page.battery.temperature_c, "°C", 1) }
        Repeater {
            model: page.battery.chargers || []
            Column {
                required property var modelData
                width: body.width
                spacing: 12
                DetailRow { width: parent.width; label: "Charger"; value: modelData.status }
                DetailRow { width: parent.width; label: "USB input limit"; value: page.amount(modelData.input_limit_ma, "mA") }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Net current is what enters (+) or leaves (−) the battery. The USB input limit is a configured ceiling, not measured charge current. Charging policy is not changed from Settings."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 12
        }
    }
}
