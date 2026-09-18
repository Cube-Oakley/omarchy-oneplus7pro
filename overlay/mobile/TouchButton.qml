import QtQuick

Rectangle {
    id: button
    property string label: ""
    property bool selected: false
    property int textSize: 16
    signal clicked()
    implicitHeight: 56
    radius: 12
    color: tap.pressed ? MobileTheme.muted : selected ? MobileTheme.selection : MobileTheme.surface
    border.width: selected ? 1 : 0
    border.color: MobileTheme.accent
    Text { font.family: MobileTheme.fontFamily;
        anchors.fill: parent
        anchors.margins: 8
        text: button.label
        color: MobileTheme.foreground
        font.pixelSize: button.textSize
        font.bold: button.selected
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    TapHandler { id: tap; onTapped: button.clicked() }
}
