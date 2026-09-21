import QtQuick
import QtTest

TestCase {
    name: "CrtPhases"
    CrtPhases { id: phases }

    function test_off_starts_full_and_ends_collapsed() {
        const start = phases.sample("off", 0);
        const end = phases.sample("off", 1);
        compare(start.stretch, 1);
        compare(start.collapse, 1);
        verify(end.stretch < 0.02);
        compare(end.collapse, 0);
    }

    function test_off_squashes_before_the_line_retracts() {
        const mid = phases.sample("off", 0.4);
        const late = phases.sample("off", 0.85);
        verify(mid.stretch < 1);
        compare(mid.collapse, 1);
        verify(late.stretch < 0.02);
        verify(late.collapse < 1);
        verify(late.collapse > 0);
    }

    function test_on_opens_the_line_before_the_picture() {
        const start = phases.sample("on", 0);
        const early = phases.sample("on", 0.2);
        const end = phases.sample("on", 1);
        compare(start.collapse, 0);
        verify(start.stretch < 0.02);
        verify(early.collapse > 0.2);
        verify(early.stretch < 0.02);
        compare(end.collapse, 1);
        verify(end.stretch > 0.99);
        verify(end.beam < 0.05);
    }
}
