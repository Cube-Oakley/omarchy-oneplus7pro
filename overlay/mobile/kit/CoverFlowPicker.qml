import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item {
    id: picker
    property var items: []
    property int currentIndex: 0
    property bool showLabels: true
    property int motionDuration: 0
    property size thumbnailSize: Qt.size(768, 432)
    property real skewOffset: 16
    property color accent: "#7aa2f7"
    property color surface: "#24283b"
    property color foreground: "#c0caf5"
    property color dim: "#1a1b26"
    property string fontFamily: "sans-serif"
    readonly property var currentItem: (currentIndex >= 0 && currentIndex < items.length) ? items[currentIndex] : ({})
    readonly property bool dragging: drag.active
    readonly property real dragX: dragging ? drag.persistentTranslation.x : 0
    readonly property real carouselFocus: currentIndex - dragX / Math.max(sliceWidth * 1.35, 48)
    signal chosen(string id)

    function wrapIndex(index) {
        const count = items.length;
        if (count <= 0)
            return 0;
        return ((index % count) + count) % count;
    }

    function selectIndex(index, immediate) {
        if (items.length === 0)
            return;
        const next = wrapIndex(index);
        if (immediate === true) {
            const previous = motionDuration;
            motionDuration = 0;
            currentIndex = next;
            motionDuration = previous;
            return;
        }
        currentIndex = next;
    }

    function selectAdjacent(direction) {
        if (items.length <= 1 || direction === 0)
            return;
        selectIndex(currentIndex + direction);
    }

    function activate() {
        const item = currentItem;
        if (item && item.id)
            chosen(item.id);
    }

    clip: false

    readonly property real expandedWidth: Math.min(width * 0.72, Math.max(240, width - 72))
    readonly property real expandedHeight: Math.max(150, expandedWidth * 0.62)
    readonly property real sliceWidth: Math.max(48, width * 0.12)
    readonly property real sliceHeight: expandedHeight * 0.91
    readonly property real sliceSpacing: -Math.round(sliceWidth * 0.28)
    readonly property real itemStep: sliceWidth + sliceSpacing
    readonly property real previewX: (width - expandedWidth) / 2
    function slotX(rel) {
        if (rel <= 0)
            return previewX + rel * itemStep;
        if (rel >= 1)
            return previewX + expandedWidth + sliceSpacing + (rel - 1) * itemStep;
        return previewX + rel * (expandedWidth + sliceSpacing);
    }

    Item {
        id: stage
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: parent.width
        height: picker.expandedHeight

        Repeater {
            model: picker.items

            delegate: Item {
                id: card
                required property int index
                required property var modelData
                readonly property real rel: index - picker.carouselFocus
                readonly property real sel: Math.max(0, Math.min(1, 1 - Math.abs(rel)))
                readonly property bool selected: Math.abs(rel) < 0.5
                readonly property bool nearby: Math.abs(rel) <= 8
                property bool sourceActivated: nearby
                onNearbyChanged: if (nearby) sourceActivated = true
                visible: nearby
                width: picker.sliceWidth + (picker.expandedWidth - picker.sliceWidth) * sel
                height: picker.sliceHeight + (picker.expandedHeight - picker.sliceHeight) * sel
                x: picker.slotX(rel)
                y: (picker.expandedHeight - height) / 2
                z: 100 - Math.min(Math.abs(rel) * 15, 70)
                Behavior on x { enabled: !picker.dragging && picker.motionDuration > 0; NumberAnimation { duration: picker.motionDuration; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !picker.dragging && picker.motionDuration > 0; NumberAnimation { duration: picker.motionDuration; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: !picker.dragging && picker.motionDuration > 0; NumberAnimation { duration: picker.motionDuration; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: !picker.dragging && picker.motionDuration > 0; NumberAnimation { duration: picker.motionDuration; easing.type: Easing.OutCubic } }

                readonly property real skAbs: Math.abs(picker.skewOffset)
                readonly property real topLeft: picker.skewOffset >= 0 ? skAbs : 0
                readonly property real topRight: picker.skewOffset >= 0 ? width : width - skAbs
                readonly property real bottomRight: picker.skewOffset >= 0 ? width - skAbs : width
                readonly property real bottomLeft: picker.skewOffset >= 0 ? 0 : skAbs

                Item {
                    id: maskShape
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Shape {
                        anchors.fill: parent
                        antialiasing: true
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: "white"
                            strokeColor: "transparent"
                            startX: card.topLeft; startY: 0
                            PathLine { x: card.topRight; y: 0 }
                            PathLine { x: card.bottomRight; y: card.height }
                            PathLine { x: card.bottomLeft; y: card.height }
                            PathLine { x: card.topLeft; y: 0 }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: maskShape
                        maskThresholdMin: 0.3
                        maskSpreadAtMin: 0.3
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: modelData.color || picker.surface
                    }
                    Image {
                        anchors.fill: parent
                        source: card.sourceActivated && modelData.url ? modelData.url : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        retainWhileLoading: true
                        smooth: true
                        sourceSize: picker.thumbnailSize
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(picker.dim.r, picker.dim.g, picker.dim.b, 0.42 * (1 - card.sel))
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !modelData.url
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: modelData.label || ""
                        color: picker.foreground
                        font.family: picker.fontFamily
                        font.pixelSize: 11 + 6 * card.sel
                    }
                }

                Shape {
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: card.selected ? picker.accent : Qt.rgba(picker.foreground.r, picker.foreground.g, picker.foreground.b, 0.35)
                        strokeWidth: card.selected ? 3 : 1
                        startX: card.topLeft; startY: 0
                        PathLine { x: card.topRight; y: 0 }
                        PathLine { x: card.bottomRight; y: card.height }
                        PathLine { x: card.bottomLeft; y: card.height }
                        PathLine { x: card.topLeft; y: 0 }
                    }
                }

                TapHandler {
                    onTapped: {
                        if (card.selected)
                            picker.activate();
                        else
                            picker.selectIndex(card.index);
                    }
                }
            }
        }

        DragHandler {
            id: drag
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: {
                if (active || picker.items.length === 0)
                    return;
                const step = Math.max(picker.sliceWidth * 1.35, 48);
                const vx = centroid.velocity.x;
                const coast = Math.abs(vx) > 700 ? vx / 420 : 0;
                const flung = picker.currentIndex - persistentTranslation.x / step - coast;
                const next = Math.max(0, Math.min(picker.items.length - 1, Math.round(flung)));
                persistentTranslation.x = 0;
                picker.selectIndex(next);
            }
        }
    }

    Text {
        visible: picker.showLabels
        anchors.top: stage.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        width: picker.expandedWidth
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: currentItem.label || ""
        color: picker.foreground
        font.family: picker.fontFamily
        font.pixelSize: 20
        font.bold: true
    }
}
