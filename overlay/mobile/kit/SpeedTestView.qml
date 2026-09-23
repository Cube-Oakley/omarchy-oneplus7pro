import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: test
    spacing: 14
    property string phase: ""
    property string message: ""
    property real pingMs: 0
    property real downMbps: 0
    property real upMbps: 0
    readonly property bool running: proc.running
    function start() {
        if (proc.running) return;
        phase = "start";
        message = "";
        pingMs = 0;
        downMbps = 0;
        upMbps = 0;
        proc.running = true;
    }
    function ingest(line) {
        let row;
        try { row = JSON.parse(line); }
        catch (e) { return; }
        phase = row.phase || phase;
        if (row.ms !== undefined) pingMs = row.ms;
        if (row.phase === "download" && row.mbps !== undefined) downMbps = row.mbps;
        if (row.phase === "upload" && row.mbps !== undefined) upMbps = row.mbps;
        if (row.phase === "done") {
            pingMs = row.ping_ms || pingMs;
            downMbps = row.download_mbps || downMbps;
            upMbps = row.upload_mbps || upMbps;
        }
        if (row.error) message = row.error;
    }
    Process {
        id: proc
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-speedtest"]
        stdout: SplitParser { onRead: line => test.ingest(line) }
        onExited: code => {
            if (code !== 0 && !test.message)
                test.message = "Speed test failed. Check the connection and try again.";
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: test.message || (test.running ? (test.phase === "ping" ? "Measuring latency…" : test.phase === "download" ? "Downloading…" : test.phase === "upload" ? "Uploading…" : "Starting…") : "Measures HTTP throughput to Cloudflare. Not ICMP ping, and not an ISP plan number.")
        color: MobileTheme.secondary
        font.family: MobileTheme.fontFamily
        font.pixelSize: 13
    }
    RowLayout {
        Layout.fillWidth: true
        SpeedGauge { Layout.fillWidth: true; title: "Latency"; unit: "ms"; ceiling: 200; value: test.pingMs }
        SpeedGauge { Layout.fillWidth: true; title: "Down"; unit: "Mbps"; ceiling: 200; value: test.downMbps }
        SpeedGauge { Layout.fillWidth: true; title: "Up"; unit: "Mbps"; ceiling: 100; value: test.upMbps }
    }
    TouchButton {
        Layout.fillWidth: true
        implicitHeight: 52
        label: test.running ? "Running…" : "Start speed test"
        enabled: !test.running
        selected: true
        onClicked: test.start()
    }
}
