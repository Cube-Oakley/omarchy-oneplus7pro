import QtQuick
import QtTest
import "."

TestCase {
    name: "SnapPager"
    when: windowShown
    SnapPager { id: pager }
    function test_short_drag_returns() {
        compare(pager.target(1, 4, -20, 200, 0), 1);
        compare(pager.target(1, 4, 20, 200, 0), 1);
    }
    function test_past_threshold_commits_one_card() {
        compare(pager.target(1, 4, -50, 200, 0), 2);
        compare(pager.target(1, 4, 50, 200, 0), 0);
    }
    function test_long_drag_lands_on_the_card_under_the_finger() {
        compare(pager.target(0, 5, -340, 200, 0), 2);
        compare(pager.target(3, 5, 330, 200, 0), 1);
    }
    function test_flick_moves_even_when_the_drag_is_short() {
        compare(pager.target(1, 4, -10, 200, -1200), 2);
        compare(pager.target(1, 4, 10, 200, 1200), 0);
    }
    function test_ends_do_not_wrap() {
        compare(pager.target(0, 3, 80, 200, 2000), 0);
        compare(pager.target(2, 3, -80, 200, -2000), 2);
    }
}
