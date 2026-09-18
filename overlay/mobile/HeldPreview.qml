import QtQuick

// Mirror the existing rendered card instead of replacing it with a small label.
// hideSource preserves its touch grab; the mirror never accepts input.
Item {
    id: preview
    property bool active: false
    property Item sourceCard: null
    property point originPoint: Qt.point(0, 0)
    property point pickupPoint: Qt.point(0, 0)
    property point currentPoint: Qt.point(0, 0)
    readonly property real distance: Math.hypot(currentPoint.x - pickupPoint.x, currentPoint.y - pickupPoint.y)
    property real liftScale: active ? 0.94 : 1
    visible: active && sourceCard !== null
    width: sourceCard ? sourceCard.width : 0
    height: sourceCard ? sourceCard.height : 0
    x: originPoint.x + currentPoint.x - pickupPoint.x
    y: originPoint.y + currentPoint.y - pickupPoint.y
    opacity: 0.86 - Math.min(1, distance / 180) * 0.44
    Behavior on liftScale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    transform: Scale {
        origin.x: preview.pickupPoint.x - preview.originPoint.x
        origin.y: preview.pickupPoint.y - preview.originPoint.y
        xScale: preview.liftScale; yScale: preview.liftScale
    }
    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: preview.active ? preview.sourceCard : null
        hideSource: preview.active
        live: false
    }
}
