pragma library

function normalizeIdList(list) {
    var input = Array.isArray(list) ? list : [];
    var normalized = [];
    var seen = {};

    for (var i = 0; i < input.length; i += 1) {
        var value = String(input[i] || "");
        if (!value || seen[value]) {
            continue;
        }

        seen[value] = true;
        normalized.push(value);
    }

    return normalized;
}

function hasId(list, eventId) {
    var normalized = normalizeIdList(list);
    return normalized.indexOf(String(eventId || "")) !== -1;
}

function mergeSeenEventIds(existingIds, events) {
    var merged = normalizeIdList(existingIds);

    for (var i = 0; i < events.length; i += 1) {
        var eventId = String(events[i].eventId || "");
        if (eventId && merged.indexOf(eventId) === -1) {
            merged.push(eventId);
        }
    }

    return merged;
}

function markEventRead(existingIds, eventId) {
    var merged = normalizeIdList(existingIds);
    var normalizedId = String(eventId || "");

    if (normalizedId && merged.indexOf(normalizedId) === -1) {
        merged.push(normalizedId);
    }

    return merged;
}

function formatCopyPayload(eventData) {
    var eventItem = eventData || {};
    return "[" + String(eventItem.category || "other") + "] "
        + String(eventItem.ts || "") + " "
        + String(eventItem.message || "");
}
