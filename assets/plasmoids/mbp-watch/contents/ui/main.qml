pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtCore

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

import "../code/constants.js" as Constants
import "../code/dataSource.js" as DataSource
import "../code/eventStore.js" as EventStore
import "../code/eventsModel.js" as EventsModel
import "../code/notifications.js" as Notifications
import "../code/openDashboard.js" as OpenDashboard
import "../code/stateAdapter.js" as StateAdapter
import "popups"
import "theme"
import "blocks"

PlasmoidItem {
    id: root

    property var sourceState: ({
        status: "loading",
        data: null,
        lastValidData: null,
        error: "",
        loadedAt: "",
    })
    property var adaptedState: StateAdapter.adapt(null)
    property var eventsState: ({
        events: [],
        indicators: [],
        newEvents: [],
    })
    property var backupState: ({
        status: "fail",
        snapshot_count: 0,
        total_size_gb: 0,
        last_snapshot_time: "",
        last_snapshot_id: "",
        error: "",
        server: "",
        server_status: "fail",
    })
    property var selectedEvent: null
    property real contentHeightHint: 720

    readonly property int counterMax: Math.max(
        adaptedState.counters.wifi,
        adaptedState.counters.connectivity,
        adaptedState.counters.gpu,
        adaptedState.counters.bluetooth,
        adaptedState.counters.thermal,
        adaptedState.counters.pm,
        1
    )

    component MetricRow: RowLayout {
        id: metricRow

        property string lbl: ""
        property string val: ""
        property string note: ""
        property real ratio: 0.0
        property color valColor: theme.ok

        spacing: 0
        Layout.fillWidth: true

        Text {
            text: metricRow.lbl
            font.family: theme.monoFont
            font.pixelSize: 11
            color: theme.textMuted
            Layout.preferredWidth: 88
            Layout.maximumWidth: 88
            elide: Text.ElideRight
        }
        Text {
            text: metricRow.val
            font.family: theme.monoFont
            font.pixelSize: 11
            color: metricRow.valColor
            Layout.preferredWidth: 72
            Layout.maximumWidth: 72
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
        Text {
            text: metricRow.note
            font.family: theme.monoFont
            font.pixelSize: 10
            color: theme.textMuted
            Layout.fillWidth: true
            elide: Text.ElideRight
            leftPadding: 6
        }
        Rectangle {
            Layout.preferredWidth: 48
            Layout.maximumWidth: 48
            Layout.preferredHeight: 3
            radius: 2
            color: theme.barBg
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, metricRow.ratio))
                height: parent.height
                radius: parent.radius
                color: metricRow.valColor
            }
        }
    }

    component HudSep: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 5
        Layout.bottomMargin: 5
        Layout.preferredHeight: 1
        color: theme.borderSoft
    }

    implicitWidth: 360
    implicitHeight: contentHeightHint + theme.spacingMd * 2

    Theme { id: theme }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.title: "MBP Watch"
    Plasmoid.icon: "utilities-system-monitor"

    function backupStatusPath() {
        var homePath = StandardPaths.writableLocation(StandardPaths.HomeLocation).toString();
        if (homePath.indexOf("file://") === 0) {
            homePath = homePath.replace("file://", "");
        }

        return homePath + "/.config/cachyos-migration-tool/backup-status.json";
    }

    function backupStatusCommand() {
        return "/usr/bin/sh -c 'cat " + backupStatusPath() + "'";
    }

    function resetBackupState(errorMessage) {
        backupState = {
            status: "fail",
            snapshot_count: 0,
            total_size_gb: 0,
            last_snapshot_time: "",
            last_snapshot_id: "",
            error: errorMessage,
            server: "",
            server_status: "fail",
        };
    }

    function readCachedJson(configKey) {
        var cached = Plasmoid.configuration[configKey] || "";
        if (!cached) {
            return null;
        }

        try {
            return JSON.parse(cached);
        } catch (e) {
            return null;
        }
    }

    function cacheJson(configKey, payload) {
        if (!payload) {
            return;
        }

        try {
            Plasmoid.configuration[configKey] = JSON.stringify(payload);
        } catch (e) {
        }
    }

    function applyBackupStatusPayload(payload) {
        if (!payload) {
            resetBackupState("No data");
            return;
        }

        try {
            backupState = JSON.parse(payload);
            cacheJson("cachedBackupJson", backupState);
        } catch (e) {
            resetBackupState("Invalid data");
        }
    }

    function extractBackupPayload(data) {
        if (!data) {
            return "";
        }

        var candidateKeys = ["stdout", "data", "output"];
        for (var i = 0; i < candidateKeys.length; i += 1) {
            var key = candidateKeys[i];
            if (typeof data[key] === "string" && data[key].length > 0) {
                return data[key];
            }
        }

        for (var prop in data) {
            if (typeof data[prop] === "string" && data[prop].trim().charAt(0) === "{") {
                return data[prop];
            }
        }

        return "";
    }

    function refreshData() {
        sourceState = DataSource.readState({
            dataUrl: Plasmoid.configuration.dataUrl || Constants.DATA_JSON_URL,
        }, sourceState);
        if (sourceState.data) {
            adaptedState = StateAdapter.adapt(sourceState.data);
            cacheJson("cachedDataJson", sourceState.data);
        } else if (sourceState.lastValidData) {
            adaptedState = StateAdapter.adapt(sourceState.lastValidData);
        }
        syncEvents();
        refreshBackupData();
    }

    function refreshBackupData() {
        backupStatusSource.connectedSources = [];
        backupStatusSource.connectedSources = [backupStatusCommand()];
    }

    function syncEvents() {
        var storeState = {
            seenEventIds: Plasmoid.configuration.seenEventIds || [],
            readEventIds: Plasmoid.configuration.readEventIds || [],
        };

        eventsState = EventsModel.buildModel(adaptedState.recentEvents, storeState);

        if (eventsState.newEvents.length > 0) {
            notifyNewEvents(eventsState.newEvents);
            Plasmoid.configuration.seenEventIds = EventStore.mergeSeenEventIds(
                storeState.seenEventIds,
                eventsState.newEvents
            );
        }
    }

    function openDashboard() {
        OpenDashboard.openDashboard(Plasmoid.configuration.dashboardUrl || Constants.DASHBOARD_URL);
    }

    function notifyNewEvents(newEvents) {
        for (var i = 0; i < newEvents.length; i += 1) {
            Notifications.notifyNewEvent(root, newEvents[i], function() {
                root.openDashboard();
            });
        }
    }

    function markEventRead(eventData) {
        if (!eventData || !eventData.eventId) {
            return;
        }

        Plasmoid.configuration.readEventIds = EventStore.markEventRead(
            Plasmoid.configuration.readEventIds || [],
            eventData.eventId
        );
        selectedEvent = null;
        syncEvents();
    }

    Timer {
        id: refreshTimer
        interval: Plasmoid.configuration.refreshMs || Constants.REFRESH_MS
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshData()
    }

    P5Support.DataSource {
        id: backupStatusSource
        engine: "executable"

        onNewData: function(sourceName, data) {
            if (sourceName !== root.backupStatusCommand()) {
                return;
            }

            root.applyBackupStatusPayload(root.extractBackupPayload(data));
        }
    }

    Component.onCompleted: {
        var cachedData = readCachedJson("cachedDataJson");
        if (cachedData) {
            adaptedState = StateAdapter.adapt(cachedData);
        }

        var cachedBackup = readCachedJson("cachedBackupJson");
        if (cachedBackup) {
            backupState = cachedBackup;
        }

        root.refreshData();
    }

    fullRepresentation: Item {
        id: fullView

        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: theme.radiusLg
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#08110c" }
                GradientStop { position: 1.0; color: "#0d1a12" }
            }
            border.width: 1
            border.color: theme.border
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: theme.spacingMd
            spacing: 3
            onImplicitHeightChanged: root.contentHeightHint = implicitHeight

            Component.onCompleted: root.contentHeightHint = implicitHeight

            // ── HEADER ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: theme.severityColor(root.adaptedState.severity.className)
                }

                Text {
                    text: "MBP WATCH"
                    font.family: theme.monoFont
                    font.pixelSize: 14
                    font.bold: true
                    color: theme.text
                    Layout.fillWidth: true
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: sevLabel.implicitWidth + 10
                    radius: 4
                    color: "transparent"
                    border.width: 1
                    border.color: theme.severityColor(root.adaptedState.severity.className)

                    Text {
                        id: sevLabel
                        anchors.centerIn: parent
                        text: root.adaptedState.severity.className.toUpperCase()
                        font.family: theme.monoFont
                        font.pixelSize: 10
                        color: theme.severityColor(root.adaptedState.severity.className)
                    }
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: hudLabel.implicitWidth + 10
                    radius: 4
                    color: "transparent"
                    border.width: 1
                    border.color: theme.borderSoft

                    Text {
                        id: hudLabel
                        anchors.centerIn: parent
                        text: "HUD"
                        font.family: theme.monoFont
                        font.pixelSize: 10
                        color: theme.textMuted
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.openDashboard()
                    }
                }
            }

            Text {
                text: root.adaptedState.generated || "—"
                font.family: theme.monoFont
                font.pixelSize: 10
                color: theme.textDim
            }

            HudSep {}

            // ── SEVERITY ─────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.adaptedState.severity.title
                    font.family: theme.monoFont
                    font.pixelSize: 12
                    color: theme.severityColor(root.adaptedState.severity.className)
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: openLabel.implicitWidth + 10
                    radius: 4
                    color: "transparent"
                    border.width: 1
                    border.color: theme.borderSoft

                    Text {
                        id: openLabel
                        anchors.centerIn: parent
                        text: "OPEN"
                        font.family: theme.monoFont
                        font.pixelSize: 10
                        color: theme.textMuted
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.openDashboard()
                    }
                }
            }

            Text {
                text: root.adaptedState.severity.text
                font.family: theme.monoFont
                font.pixelSize: 10
                color: theme.textMuted
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            HudSep {}

            // ── COUNTERS ─────────────────────────────────────────────
            MetricRow {
                lbl: "Wi-Fi"
                val: String(root.adaptedState.counters.wifi)
                ratio: root.adaptedState.counters.wifi / root.counterMax
                valColor: root.adaptedState.counters.wifi > 0 ? theme.warn : theme.textDim
            }
            MetricRow {
                lbl: "Connectivity"
                val: String(root.adaptedState.counters.connectivity)
                ratio: root.adaptedState.counters.connectivity / root.counterMax
                valColor: root.adaptedState.counters.connectivity > 0 ? theme.warn : theme.textDim
            }
            MetricRow {
                lbl: "GPU/DRM"
                val: String(root.adaptedState.counters.gpu)
                ratio: root.adaptedState.counters.gpu / root.counterMax
                valColor: root.adaptedState.counters.gpu > 0 ? theme.warn : theme.textDim
            }
            MetricRow {
                lbl: "Bluetooth"
                val: String(root.adaptedState.counters.bluetooth)
                ratio: root.adaptedState.counters.bluetooth / root.counterMax
                valColor: root.adaptedState.counters.bluetooth > 0 ? theme.warn : theme.textDim
            }
            MetricRow {
                lbl: "Thermal/ACPI"
                val: String(root.adaptedState.counters.thermal)
                ratio: root.adaptedState.counters.thermal / root.counterMax
                valColor: root.adaptedState.counters.thermal > 0 ? theme.warn : theme.textDim
            }
            MetricRow {
                lbl: "Suspend/PM"
                val: String(root.adaptedState.counters.pm)
                ratio: root.adaptedState.counters.pm / root.counterMax
                valColor: root.adaptedState.counters.pm > 0 ? theme.warn : theme.textDim
            }

            HudSep {}

            // ── SNAPSHOT ─────────────────────────────────────────────
            MetricRow {
                lbl: "Thermal"
                val: root.adaptedState.snapshot.primaryTemperature.currentC !== null
                    ? root.adaptedState.snapshot.primaryTemperature.currentC + "°C" : "—"
                note: root.adaptedState.snapshot.fan.text
                ratio: root.adaptedState.snapshot.primaryTemperature.ratio
                valColor: root.adaptedState.snapshot.primaryTemperature.ratio > 0.85
                    ? theme.critical
                    : root.adaptedState.snapshot.primaryTemperature.ratio > 0.65
                        ? theme.warn : theme.ok
            }
            MetricRow {
                lbl: "CPU"
                val: root.adaptedState.snapshot.cpu.usage || "—"
                note: root.adaptedState.snapshot.cpu.governor
                ratio: (parseInt(root.adaptedState.snapshot.cpu.usage) || 0) / 100
                valColor: (parseInt(root.adaptedState.snapshot.cpu.usage) || 0) > 90
                    ? theme.critical
                    : (parseInt(root.adaptedState.snapshot.cpu.usage) || 0) > 70
                        ? theme.warn : theme.ok
            }
            MetricRow {
                lbl: "Battery"
                val: root.adaptedState.snapshot.battery.percentage !== null
                    ? root.adaptedState.snapshot.battery.percentage + "%" : "—"
                note: root.adaptedState.snapshot.battery.state
                ratio: (root.adaptedState.snapshot.battery.percentage || 0) / 100
                valColor: root.adaptedState.snapshot.battery.tone === "critical"
                    ? theme.critical
                    : root.adaptedState.snapshot.battery.tone === "warn"
                        ? theme.warn : theme.ok
            }
            MetricRow {
                lbl: "Wi-Fi"
                val: root.adaptedState.snapshot.wifi.ssid
                    || (root.adaptedState.snapshot.wifi.connected ? "—" : "off")
                note: root.adaptedState.snapshot.wifi.signalDbm !== null
                    ? (root.adaptedState.snapshot.wifi.signalDbm + " dBm"
                        + (root.adaptedState.snapshot.wifi.latencyMs !== null
                            ? " / " + root.adaptedState.snapshot.wifi.latencyMs + " ms" : ""))
                    : ""
                ratio: root.adaptedState.snapshot.wifi.signalDbm !== null
                    ? Math.max(0, Math.min(1, (root.adaptedState.snapshot.wifi.signalDbm + 90) / 60))
                    : 0
                valColor: root.adaptedState.snapshot.wifi.tone === "critical"
                    ? theme.critical
                    : root.adaptedState.snapshot.wifi.tone === "warn"
                        ? theme.warn : theme.ok
            }

            HudSep {}

            // ── LOAD ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "Load"
                    font.family: theme.monoFont
                    font.pixelSize: 11
                    color: theme.textMuted
                    Layout.preferredWidth: 100
                }
                Text {
                    text: root.adaptedState.snapshot.loadAndSystem.loadAverage || "—"
                    font.family: theme.monoFont
                    font.pixelSize: 11
                    color: theme.text
                    Layout.fillWidth: true
                }
            }

            HudSep {}

            // ── BACKUP ───────────────────────────────────────────────
            BackupStatusBlock {
                Layout.fillWidth: true
                backup: root.backupState
            }

            HudSep {}

            // ── EVENTS ───────────────────────────────────────────────
            Flow {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Events"
                    font.family: theme.monoFont
                    font.pixelSize: 11
                    color: theme.textMuted
                }

                Repeater {
                    model: root.eventsState.indicators
                    delegate: Rectangle {
                        id: eventChip
                        required property var modelData

                        implicitHeight: 20
                        implicitWidth: evtLabel.implicitWidth + 10
                        radius: 4
                        color: "transparent"
                        border.width: 1
                        border.color: eventChip.modelData.unread > 0 ? theme.warn : theme.borderSoft

                        Text {
                            id: evtLabel
                            anchors.centerIn: parent
                            text: eventChip.modelData.category.toUpperCase() + " " + eventChip.modelData.total
                            font.family: theme.monoFont
                            font.pixelSize: 10
                            color: eventChip.modelData.unread > 0 ? theme.warn : theme.textDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectedEvent = eventChip.modelData.latestEvent
                        }
                    }
                }

                Item {
                    implicitWidth: 1
                    implicitHeight: 1
                }
            }

            // ── DRIVERS ──────────────────────────────────────────────
            Repeater {
                model: root.adaptedState.driverHealth.drivers
                delegate: RowLayout {
                    id: driverRow
                    required property var modelData
                    required property int index

                    spacing: 0
                    Layout.fillWidth: true

                    Text {
                        text: driverRow.index === 0 ? "Driver" : ""
                        font.family: theme.monoFont
                        font.pixelSize: 11
                        color: theme.textMuted
                        Layout.preferredWidth: 100
                    }
                    Rectangle {
                        Layout.preferredWidth: 7
                        Layout.preferredHeight: 7
                        radius: 4
                        color: driverRow.modelData.status === "OK" ? theme.ok : theme.critical
                    }
                    Text {
                        text: " " + driverRow.modelData.name
                        font.family: theme.monoFont
                        font.pixelSize: 11
                        color: theme.text
                        Layout.preferredWidth: 70
                        elide: Text.ElideRight
                    }
                    Text {
                        text: driverRow.modelData.detail
                        font.family: theme.monoFont
                        font.pixelSize: 10
                        color: theme.textMuted
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        leftPadding: 6
                    }
                }
            }

            // ── FOOTER ───────────────────────────────────────────────
            Text {
                text: "↻ " + (Plasmoid.configuration.refreshMs || Constants.REFRESH_MS) + " ms"
                font.family: theme.monoFont
                font.pixelSize: 10
                color: theme.textDim
                Layout.topMargin: 4
            }
        }

        EventPopup {
            eventData: root.selectedEvent
            ttlMs: Plasmoid.configuration.eventPopupTtlMs || Constants.EVENT_POPUP_TTL_MS
            onCloseRequested: root.selectedEvent = null
            onMarkReadRequested: root.markEventRead(eventData)
            onDashboardRequested: root.openDashboard()
        }
    }
}
