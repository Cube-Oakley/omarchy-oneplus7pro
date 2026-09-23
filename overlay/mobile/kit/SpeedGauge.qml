import QtQuick

Item {
    id: gauge
    property real value: 0
    property real ceiling: 200
    property string unit: "Mbps"
    property string title: ""
    implicitWidth: 128
    implicitHeight: 148
    onValueChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2;
            const cy = height / 2 + 6;
            const r = Math.min(width, height) / 2 - 14;
            ctx.lineWidth = 9;
            ctx.lineCap = "round";
            ctx.strokeStyle = "" + MobileTheme.muted;
            ctx.beginPath();
            ctx.arc(cx, cy, r, Math.PI * 0.75, Math.PI * 2.25);
            ctx.stroke();
            const t = Math.max(0, Math.min(1, Number(gauge.value) / gauge.ceiling));
            if (t <= 0) return;
            ctx.strokeStyle = "" + MobileTheme.accent;
            ctx.beginPath();
            ctx.arc(cx, cy, r, Math.PI * 0.75, Math.PI * 0.75 + t * Math.PI * 1.5);
            ctx.stroke();
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: gauge.value ? Number(gauge.value).toFixed(gauge.unit === "ms" ? 0 : 1) : "—"
            color: MobileTheme.foreground
            font.family: MobileTheme.fontFamily
            font.pixelSize: 22
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: gauge.unit
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 11
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: gauge.title
            color: MobileTheme.accent
            font.family: MobileTheme.fontFamily
            font.pixelSize: 12
        }
    }
}
