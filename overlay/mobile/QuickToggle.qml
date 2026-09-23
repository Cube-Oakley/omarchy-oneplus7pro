import QtQuick

Rectangle {
    id: toggle
    property string symbol: ""
    property string label: ""
    property bool active: false
    property bool enabled: true
    signal clicked()
    implicitHeight: 72
    radius: MobileTheme.radius(18)
    opacity: enabled ? 1 : 0.45
    color: tap.pressed ? MobileTheme.muted : active ? MobileTheme.selection : MobileTheme.surface
    border.width: active ? 1 : 0
    border.color: MobileTheme.accent
    Column {
        anchors.centerIn: parent
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: toggle.symbol
            color: toggle.active ? MobileTheme.accent : MobileTheme.foreground
            font.family: MobileTheme.fontFamily
            font.pixelSize: 20
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: toggle.label
            color: MobileTheme.foreground
            font.family: MobileTheme.fontFamily
            font.pixelSize: 12
        }
    }
    TapHandler { id: tap; enabled: toggle.enabled; onTapped: toggle.clicked() }
}
