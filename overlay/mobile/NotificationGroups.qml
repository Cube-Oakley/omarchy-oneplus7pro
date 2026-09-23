import QtQuick

QtObject {
    function grouped(items) {
        const groups = [];
        const index = {};
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const key = (item && item.appName) ? item.appName : "Notification";
            if (index[key] === undefined) {
                index[key] = groups.length;
                groups.push({key: key, appName: key, items: []});
            }
            groups[index[key]].items.push(item);
        }
        return groups;
    }
    function dismissAll(items) {
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (item && typeof item.dismiss === "function") item.dismiss();
        }
    }
}
