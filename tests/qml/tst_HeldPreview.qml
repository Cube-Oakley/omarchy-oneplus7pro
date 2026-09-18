import QtQuick
import QtTest
import "."

TestCase {
    id: test
    name: "HeldPreview"
    when: windowShown
    visible: true
    width: 480; height: 800
    property int releases: 0
    Rectangle {
        id: card
        x: 30; y: 200; width: 400; height: 550; color: "green"
        PreviewGestures {
            id: gesture; anchors.fill: parent
            onHeld: p => { mirror.originPoint = Qt.point(card.x, card.y); mirror.pickupPoint = p; mirror.currentPoint = p; mirror.active = true; }
            onHoldMoved: p => mirror.currentPoint = p
            onHoldFinished: p => { test.releases++; mirror.active = false; }
        }
    }
    HeldPreview { id: mirror; sourceCard: card }
    function test_large_preview_keeps_grab_and_touch_anchor() {
        const touch = touchEvent(gesture);
        touch.press(0, gesture, 160, 220).commit(); wait(650);
        verify(mirror.active); fuzzyCompare(mirror.liftScale, .94, .001);
        compare(mirror.width, card.width); compare(mirror.height, card.height);
        const before = mirror.mapToItem(test, 160, 220);
        fuzzyCompare(before.x, 190, .01); fuzzyCompare(before.y, 420, .01);
        // Move outside the original card and over the workspace row.
        touch.move(0, test, 190, 80).commit(); wait(40);
        compare(mirror.currentPoint.y, 80); verify(mirror.opacity <= .43);
        const after = mirror.mapToItem(test, 160, 220);
        fuzzyCompare(after.x, 190, .01); fuzzyCompare(after.y, 80, .01);
        touch.release(0, test, 190, 80).commit(); wait(30);
        compare(releases, 1); verify(!mirror.active);
    }
}
