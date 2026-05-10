pragma library

function openDashboard(url) {
    var dashboardUrl = String(url || "");

    if (!dashboardUrl) {
        return false;
    }

    return Qt.openUrlExternally(dashboardUrl);
}
