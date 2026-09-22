import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: wallpaper
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "omarchy-mobile-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: MobileTheme.background
    Image {
        anchors.fill: parent
        source: MobileTheme.state.wallpaper ? MobileTheme.state.wallpaper.url : ""
        sourceSize: Qt.size(Math.ceil(Screen.width * Screen.devicePixelRatio),
                            Math.ceil(Screen.height * Screen.devicePixelRatio))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        retainWhileLoading: true
        cache: true
        autoTransform: true
        onStatusChanged: {
            if (status === Image.Error) {
                MobileTheme.wallpaperError = "Wallpaper could not be opened";
                console.warn("MOBILE_WALLPAPER_FAILED " + source);
            } else if (status === Image.Ready || status === Image.Null) {
                MobileTheme.wallpaperError = "";
                console.log("MOBILE_WALLPAPER_READY " + source);
            }
        }
    }
}
