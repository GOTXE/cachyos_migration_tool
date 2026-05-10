pragma library

var DATA_JSON_PATH = "/var/lib/mbp-watch/data.json";
var DASHBOARD_URL = "http://127.0.0.1:7070/report.html";
var REFRESH_MS = 5000;
var EVENT_POPUP_TTL_MS = 30000;

function toFileUrl(path) {
    if (!path) {
        return "";
    }

    if (path.indexOf("file://") === 0) {
        return path;
    }

    return "file://" + path;
}
