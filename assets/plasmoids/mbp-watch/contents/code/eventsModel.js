
.import "eventStore.js" as EventStore

function categoryTargets(category) {
    switch (String(category || "other")) {
    case "wifi":
        return ["wifi", "connectivity"];
    case "gpu":
        return ["gpu"];
    case "power":
        return ["pm"];
    case "thermal":
        return ["thermal", "throttle"];
    case "audio":
        return ["audio"];
    case "bluetooth":
        return ["bluetooth"];
    default:
        return ["general"];
    }
}

function buildIndicators(events) {
    var counts = {};
    var indicators = [];

    for (var i = 0; i < events.length; i += 1) {
        var eventItem = events[i];
        var key = String(eventItem.category || "other");
        counts[key] = counts[key] || {
            category: key,
            total: 0,
            unread: 0,
            latestEvent: null,
        };

        counts[key].total += 1;
        if (eventItem.isUnread) {
            counts[key].unread += 1;
        }
        if (!counts[key].latestEvent) {
            counts[key].latestEvent = eventItem;
        }
    }

    for (var category in counts) {
        indicators.push(counts[category]);
    }

    return indicators;
}

function buildModel(events, storeState) {
    var eventList = Array.isArray(events) ? events : [];
    var store = storeState || {};
    var seenEventIds = EventStore.normalizeIdList(store.seenEventIds);
    var readEventIds = EventStore.normalizeIdList(store.readEventIds);
    var normalizedEvents = [];
    var newEvents = [];

    for (var i = 0; i < eventList.length; i += 1) {
        var eventItem = eventList[i] || {};
        var isSeen = EventStore.hasId(seenEventIds, eventItem.eventId);
        var isRead = EventStore.hasId(readEventIds, eventItem.eventId);
        var normalizedEvent = {
            eventId: eventItem.eventId,
            ts: eventItem.ts,
            category: eventItem.category,
            message: eventItem.message,
            targets: categoryTargets(eventItem.category),
            isNew: !isSeen,
            isRead: isRead,
            isUnread: !isRead,
        };

        normalizedEvents.push(normalizedEvent);

        if (normalizedEvent.isNew) {
            newEvents.push(normalizedEvent);
        }
    }

    return {
        events: normalizedEvents,
        indicators: buildIndicators(normalizedEvents),
        newEvents: newEvents,
    };
}
