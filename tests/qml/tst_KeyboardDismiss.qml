import QtQuick
import QtTest
import "."
TestCase {
    id: test; name: "KeyboardDismiss"; when: windowShown; visible: true
    width: 480; height: 400
    KeyboardDismiss { id: handle; x: 168; y: 150; width: 144; height: 24 }
    SignalSpy { id: dismissed; target: handle; signalName: "dismissed" }
    function init() { dismissed.clear(); }
    function swipe(x, y, dx, dy) {
        const t = touchEvent(test);
        t.press(0, test, x, y).commit(); wait(20);
        for (let i = 1; i <= 5; i++) { t.move(0, test, x+dx*i/5, y+dy*i/5).commit(); wait(20); }
        t.release(0, test, x+dx, y+dy).commit(); wait(30);
    }
    function test_down_from_handle_closes() { swipe(220, 160, 0, 80); compare(dismissed.count, 1); }
    function test_from_keys_does_not_close() { swipe(220, 190, 0, 80); compare(dismissed.count, 0); }
    function test_app_scroll_does_not_close() { swipe(50, 120, 0, 100); compare(dismissed.count, 0); }
    function test_short_pull_does_not_close() { swipe(220, 160, 0, 28); compare(dismissed.count, 0); }
    function test_up_or_sideways_does_not_close() {
        swipe(220, 160, 0, -80); swipe(220, 160, 80, 0); compare(dismissed.count, 0);
    }
}
