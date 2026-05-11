
.import "constants.js" as Constants

function buildResult(status, payload, lastValidPayload, errorMessage) {
    return {
        status: status,
        data: payload,
        lastValidData: lastValidPayload,
        error: errorMessage || "",
        loadedAt: new Date().toISOString(),
    };
}

function readTextFile(url) {
    var request = new XMLHttpRequest();

    request.open("GET", url, false);
    request.send();

    if (request.status < 200 || request.status >= 300) {
        throw new Error("HTTP " + request.status);
    }

    if (!request.responseText) {
        throw new Error("Empty response");
    }

    return request.responseText;
}

function parseJson(text) {
    return JSON.parse(text);
}

function readState(config, previousState) {
    var currentConfig = config || {};
    var priorState = previousState || {};
    var lastValidData = priorState.lastValidData || null;
    var sourcePath = currentConfig.dataUrl || Constants.DATA_JSON_URL;

    try {
        var text = readTextFile(sourcePath);
        var payload = parseJson(text);
        return buildResult("ready", payload, payload, "");
    } catch (error) {
        if (lastValidData) {
            return buildResult("degraded", lastValidData, lastValidData, String(error));
        }

        return buildResult("loading", null, null, String(error));
    }
}
