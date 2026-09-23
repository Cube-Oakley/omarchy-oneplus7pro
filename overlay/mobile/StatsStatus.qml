import QtQuick

Item {
    id: stats
    implicitWidth: 34
    implicitHeight: 24

    function fill(value) {
        if (value === null || value === undefined) return 0;
        return Math.max(0, Math.min(1, Number(value) / 100));
    }

    Column {
        anchors.centerIn: parent
        spacing: 4
        // Fixed bars: a model rebuilt on every sample recreated them.
        Repeater {
            model: 2
            Rectangle {
                id: bar
                required property int index
                width: 28; height: 5; radius: 2
                color: MobileTheme.muted
                Rectangle {
                    width: parent.width * stats.fill(bar.index === 0 ? MobileStatus.cpuPercent : MobileStatus.memoryPercent)
                    height: parent.height; radius: 2
                    color: bar.index === 0 ? MobileTheme.accent : MobileTheme.foreground
                }
            }
        }
    }
}
