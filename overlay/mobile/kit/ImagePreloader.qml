import QtQuick

Item {
    property var urls: []
    property size thumbnailSize: Qt.size(768, 432)
    visible: false
    width: 1
    height: 1
    Repeater {
        model: urls
        Image {
            required property var modelData
            width: 2
            height: 2
            source: typeof modelData === "string" ? modelData : (modelData && modelData.url) || ""
            sourceSize: thumbnailSize
            asynchronous: true
            cache: true
        }
    }
}
