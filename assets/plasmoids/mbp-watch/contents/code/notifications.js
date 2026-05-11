
function buildMessage(eventData) {
    var eventItem = eventData || {};
    return String(eventItem.category || "other").toUpperCase()
        + " • " + String(eventItem.ts || "")
        + "\n" + String(eventItem.message || "");
}

function notifyNewEvent(host, eventData, onActivate) {
    var message = buildMessage(eventData);
    var actionText = "Open dashboard";

    if (host && typeof host.showPassiveNotification === "function") {
        host.showPassiveNotification(message, 8000, actionText, onActivate);
        return true;
    }

    if (host && host.Plasmoid && host.Plasmoid.nativeInterface
            && typeof host.Plasmoid.nativeInterface.showPassiveNotification === "function") {
        host.Plasmoid.nativeInterface.showPassiveNotification(message, 8000, actionText, onActivate);
        return true;
    }

    console.log("MBP Watch notification:", message);
    return false;
}
