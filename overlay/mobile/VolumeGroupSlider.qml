import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One volume group in the volume panel: tap-to-mute icon, vertical slider,
// level and label. The slider is as wide as a thumb; the drawn track is not.
ColumnLayout {
    id: column
    required property var modelData
    property var level: ({available: false, percent: 0, muted: false})
    // Released value the backend has not confirmed yet (-1 when none), and the
    // level it replaces: answers still showing that level are not news.
    property real pending: -1
    property real pendingFrom: -1
    readonly property alias slider: slider
    signal volumeMoved(string group, real percent)
    signal muteTapped(string group)
    signal dragChanged(bool dragging)
    Layout.fillHeight: true
    Layout.preferredWidth: 60
    spacing: 8
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: !column.level.available ? "—" : column.level.muted ? "󰝟" : column.modelData.icon
        font.family: MobileTheme.fontFamily; font.pixelSize: 28
        color: column.level.available ? MobileTheme.accent : MobileTheme.secondary
        TapHandler {
            enabled: column.level.available === true
            margin: 10
            onTapped: column.muteTapped(column.modelData.id)
        }
    }
    Slider {
        id: slider
        Layout.fillHeight: true
        Layout.preferredWidth: 56
        Layout.alignment: Qt.AlignHCenter
        from: 0; to: 100; stepSize: 1
        orientation: Qt.Vertical
        enabled: column.level.available === true
        onMoved: column.volumeMoved(column.modelData.id, value)
        onPressedChanged: {
            if (!pressed) {
                column.pendingFrom = column.level.muted ? 0 : column.level.percent;
                column.pending = value;
                settle.restart();
            }
            column.dragChanged(pressed);
        }
        background: Rectangle {
            x: (slider.width - width) / 2; y: slider.topPadding
            implicitWidth: 12; implicitHeight: 160
            width: 12; height: slider.availableHeight; radius: MobileTheme.radius(6)
            color: MobileTheme.muted
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width
                height: parent.height * slider.position; radius: MobileTheme.radius(6)
                color: MobileTheme.accent
            }
        }
        handle: Rectangle {
            x: (slider.width - width) / 2
            y: slider.topPadding + slider.visualPosition * (slider.availableHeight - height)
            implicitWidth: 34; implicitHeight: 22
            radius: MobileTheme.radius(11)
            color: MobileTheme.foreground
        }
    }
    // The backend answers a moment behind the finger. Neither pull the handle
    // mid-drag nor snap it back on release before the new level is confirmed.
    Binding {
        target: slider
        property: "value"
        value: column.level.muted ? 0 : column.level.percent
        when: !slider.pressed && column.pending < 0
        restoreMode: Binding.RestoreNone
    }
    onLevelChanged: {
        const shown = level.muted ? 0 : level.percent;
        if (pending >= 0 && (Math.abs(shown - pending) <= 1 || shown !== pendingFrom))
            pending = -1;
    }
    // Without a confirmation, show the real level again rather than a guess.
    Timer { id: settle; interval: 3000; onTriggered: column.pending = -1 }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: column.level.available ? Math.round(column.slider.pressed || column.pending >= 0 ? column.slider.value : column.level.percent) + "%" : "Off"
        font.family: MobileTheme.fontFamily; font.pixelSize: 13
        color: MobileTheme.foreground
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: column.modelData.label
        font.family: MobileTheme.fontFamily; font.pixelSize: 11
        color: MobileTheme.secondary
    }
}
