import QtQuick
import QtTest
import "."

TestCase {
    name: "LeftBack"
    when: windowShown
    visible: true
    width: 480
    height: 800
    LeftBack { id: back; width: 24; height: 800 }
    SignalSpy { id: backs; target: back; signalName: "committed" }
    function init() { backs.clear(); }
    function test_inward_swipe_goes_back() {
        const touch = touchEvent(back);
        touch.press(0, back, 8, 400).commit(); wait(20);
        touch.move(0, back, 40, 402).commit(); wait(20);
        touch.move(0, back, 110, 406).commit(); wait(30);
        touch.release(0, back, 110, 406).commit(); wait(30);
        compare(backs.count, 1);
    }
    function test_vertical_drag_does_not_go_back() {
        const touch = touchEvent(back);
        touch.press(0, back, 4, 200).commit(); wait(20);
        touch.move(0, back, 20, 360).commit(); wait(30);
        touch.release(0, back, 20, 360).commit(); wait(30);
        compare(backs.count, 0);
    }
}
