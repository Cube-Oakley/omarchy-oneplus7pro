import QtQuick
import QtTest
import "."

TestCase {
    id: test
    name: "MenuOverlay"
    when: windowShown
    visible: true
    width: 480
    height: 640
    property int dismissed: 0
    MenuOverlay {
        id: overlay
        open: false
        onDismissed: test.dismissed++
        Rectangle {
            id: sheet
            objectName: "sheet"
            width: 200
            height: 80
            color: "red"
        }
    }
    function init() {
        overlay.open = false;
        dismissed = 0;
        wait(30);
    }
    function test_content_stays_mounted_while_closed() {
        compare(sheet.parent !== null, true);
        verify(sheet.width === 200);
        overlay.open = true;
        wait(50);
        verify(overlay.visible);
        overlay.open = false;
        wait(30);
        compare(sheet.parent !== null, true);
    }
    function test_scrim_tap_dismisses() {
        overlay.open = true;
        wait(40);
        const t = touchEvent(overlay);
        t.press(0, overlay, 20, 20).commit(); wait(20);
        t.release(0, overlay, 20, 20).commit(); wait(40);
        compare(dismissed, 1);
    }
}
