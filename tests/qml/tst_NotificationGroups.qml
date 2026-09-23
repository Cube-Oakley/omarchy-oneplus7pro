import QtQuick
import QtTest
import "."

TestCase {
    name: "NotificationGroups"
    NotificationGroups { id: groups }
    function test_groups_newest_app_first_and_keeps_order_inside() {
        const grouped = groups.grouped([
            {appName: "Chromium", summary: "Tab 2"},
            {appName: "NetworkManager", summary: "Wi-Fi"},
            {appName: "Chromium", summary: "Tab 1"},
            {summary: "Orphan"}
        ]);
        compare(grouped.length, 3);
        compare(grouped[0].appName, "Chromium");
        compare(grouped[0].items.length, 2);
        compare(grouped[0].items[0].summary, "Tab 2");
        compare(grouped[0].items[1].summary, "Tab 1");
        compare(grouped[1].appName, "NetworkManager");
        compare(grouped[2].appName, "Notification");
    }
    function test_dismiss_all_calls_each_item() {
        const dismissed = [];
        groups.dismissAll([
            {dismiss: () => dismissed.push("a")},
            {dismiss: () => dismissed.push("b")},
            {}
        ]);
        compare(dismissed, ["a", "b"]);
    }
}
