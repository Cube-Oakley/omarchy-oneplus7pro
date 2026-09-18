import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: wifi
    property var state: MobileStatus.wifi
    visible: state.available === true
    implicitWidth: visible ? 22 : 0
    implicitHeight: 24

    Canvas {
        id: glyph
        anchors.fill: parent
        property color foreground: MobileTheme.foreground
        property color secondary: MobileTheme.secondary
        onForegroundChanged: requestPaint()
        onSecondaryChanged: requestPaint()
        Connections { target: wifi; function onStateChanged() { glyph.requestPaint(); } }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = 1.8;
            ctx.lineCap = "round";
            for (let level = 1; level <= 3; level++) {
                const active = wifi.state.connected && (wifi.state.signal ?? 0) >= (level - 1) * 34;
                ctx.strokeStyle = active ? foreground : secondary;
                ctx.globalAlpha = active ? 1 : 0.3;
                ctx.beginPath();
                ctx.arc(11, 19, level * 4, Math.PI * 1.25, Math.PI * 1.75);
                ctx.stroke();
            }
            ctx.globalAlpha = 1;
            ctx.fillStyle = wifi.state.connected ? foreground : secondary;
            ctx.beginPath(); ctx.arc(11, 19, 1.4, 0, 2 * Math.PI); ctx.fill();
            if (!wifi.state.connected) {
                ctx.strokeStyle = secondary;
                ctx.beginPath(); ctx.moveTo(4, 6); ctx.lineTo(18, 20); ctx.stroke();
            }
        }
    }
}
