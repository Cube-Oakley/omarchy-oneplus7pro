import QtQuick
Rectangle {
    id: tile
    property string symbol: ""
    property string title: ""
    property string subtitle: ""
    property bool highlight: false
    signal clicked()
    implicitHeight: 126
    radius: 22
    color: tap.pressed ? MobileTheme.muted : highlight ? MobileTheme.selection : MobileTheme.surface
    border.width: highlight ? 1 : 0
    border.color: MobileTheme.accent
    Text { font.family: MobileTheme.fontFamily; x: 18; y: 14; text: tile.symbol; color: MobileTheme.accent; font.pixelSize: 24 }
    Text { font.family: MobileTheme.fontFamily; anchors.right: parent.right; anchors.rightMargin: 18; y: 17; text: "↗"; color: MobileTheme.secondary; font.pixelSize: 18 }
    Text { font.family: MobileTheme.fontFamily; x: 18; y: 52; width: parent.width - 36; text: tile.title; textFormat: Text.PlainText; elide: Text.ElideRight; color: MobileTheme.foreground; font.pixelSize: 20; font.bold: true }
    Text { font.family: MobileTheme.fontFamily; x: 18; y: 82; width: parent.width - 36; text: tile.subtitle; textFormat: Text.PlainText; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; color: MobileTheme.secondary; font.pixelSize: 12 }
    TapHandler { id: tap; onTapped: tile.clicked() }
}
