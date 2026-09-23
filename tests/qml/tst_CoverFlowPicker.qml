import QtQuick
import QtTest
import "."

TestCase {
    id: test
    name: "CoverFlowPicker"
    when: windowShown
    visible: true
    width: 480
    height: 640
    property var chosen: []
    CoverFlowPicker {
        id: flow
        anchors.fill: parent
        items: [
            {id: "tokyo-night", url: "", label: "tokyo night"},
            {id: "nord", url: "", label: "nord"},
            {id: "gruvbox", url: "", label: "gruvbox"}
        ]
        onChosen: id => test.chosen.push(id)
    }
    function init() {
        chosen = [];
        flow.currentIndex = 0;
        wait(20);
    }
    function test_adjacent_wraps() {
        flow.selectAdjacent(1);
        compare(flow.currentIndex, 1);
        compare(flow.currentItem.id, "nord");
        flow.selectAdjacent(1);
        flow.selectAdjacent(1);
        compare(flow.currentIndex, 0);
        flow.selectAdjacent(-1);
        compare(flow.currentItem.id, "gruvbox");
    }
    function test_swipe_left_selects_next() {
        const t = touchEvent(flow);
        t.press(0, flow, 300, 120).commit(); wait(20);
        t.move(0, flow, 240, 120).commit(); wait(20);
        t.move(0, flow, 210, 120).commit(); wait(20);
        t.release(0, flow, 210, 120).commit(); wait(40);
        verify(flow.currentIndex >= 1);
        compare(chosen.length, 0);
    }
    function test_tap_side_selects_without_applying() {
        const t = touchEvent(flow);
        t.press(0, flow, 430, 140).commit(); wait(20);
        t.release(0, flow, 430, 140).commit(); wait(40);
        compare(flow.currentIndex, 1);
        compare(chosen.length, 0);
    }
    function test_tap_center_applies() {
        const t = touchEvent(flow);
        t.press(0, flow, 240, 140).commit(); wait(20);
        t.release(0, flow, 240, 140).commit(); wait(40);
        compare(chosen, ["tokyo-night"]);
    }
}
