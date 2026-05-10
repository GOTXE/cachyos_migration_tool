pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "../code/constants.js" as Constants
import "../code/dataSource.js" as DataSource
import "../code/eventStore.js" as EventStore
import "../code/eventsModel.js" as EventsModel
import "../code/notifications.js" as Notifications
import "../code/openDashboard.js" as OpenDashboard
import "../code/stateAdapter.js" as StateAdapter
import "blocks"
import "common"
import "popups"
import "theme"

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
    property var selectedEvent: null

    implicitWidth: 360
    implicitHeight: 720

    Theme {
        id: theme
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.title: "MBP Watch"
    Plasmoid.icon: "utilities-system-monitor"

    function refreshData() {
        sourceState = DataSource.readState({
            dataPath: Plasmoid.configuration.dataPath || Constants.DATA_JSON_PATH,
        }, sourceState);
        adaptedState = StateAdapter.adapt(sourceState.data);
        syncEvents();
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

    fullRepresentation: Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            radius: theme.radiusLg
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#08110c" }
                GradientStop { position: 0.45; color: "#102018" }
                GradientStop { position: 1.0; color: "#08110c" }
            }
            border.width: 1
            border.color: theme.border
        }

        Rectangle {
            anchors.fill: parent
            radius: theme.radiusLg
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(theme.glow.r, theme.glow.g, theme.glow.b, 0.18)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: theme.spacingLg
            spacing: theme.spacingMd

            HudPanel {
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                raised: true
                accentColor: theme.severityColor(root.adaptedState.severity.className)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: theme.panelPadding
                    spacing: theme.spacingXs

                    RowLayout {
                        Layout.fillWidth: true

                        StatusDot {
                            dotColor: theme.severityColor(root.adaptedState.severity.className)
                        }

                        MonoLabel {
                            Layout.fillWidth: true
                            labelColor: theme.text
                            labelSize: 17
                            content: "MBP WATCH"
                        }

                        IconActionButton {
                            label: "HUD"
                            accentColor: theme.borderSoft
                        }
                    }

                    MonoLabel {
                        Layout.fillWidth: true
                        labelColor: theme.severityColor(root.adaptedState.severity.className)
                        labelSize: 11
                        content: root.adaptedState.severity.title + " / " + root.adaptedState.severity.className
                    }

                    MonoLabel {
                        Layout.fillWidth: true
                        labelColor: theme.textMuted
                        labelSize: 11
                        content: root.adaptedState.generated ? root.adaptedState.generated : "Awaiting telemetry snapshot"
                    }

                    ThinBar {
                        Layout.fillWidth: true
                        value: root.sourceState.status === "ready" ? 1 : root.sourceState.status === "degraded" ? 0.55 : 0.18
                        barColor: root.sourceState.status === "ready"
                            ? theme.ok
                            : root.sourceState.status === "degraded"
                                ? theme.warn
                                : theme.borderSoft
                    }
                }
            }

            SeverityBlock {
                Layout.fillWidth: true
                severity: root.adaptedState.severity
                onDashboardRequested: root.openDashboard()
            }

            CountersBlock {
                Layout.fillWidth: true
                counters: root.adaptedState.counters
            }

            SnapshotBlock {
                Layout.fillWidth: true
                snapshot: root.adaptedState.snapshot
            }

            EventIndicatorsBlock {
                Layout.fillWidth: true
                indicators: root.eventsState.indicators
                onEventActivated: root.selectedEvent = eventData
            }

            DriverHealthBlock {
                Layout.fillWidth: true
                driverHealth: root.adaptedState.driverHealth
            }

            DailyHistoryBlock {
                Layout.fillWidth: true
                dailyHistory: root.adaptedState.dailyHistory
            }

            MonoLabel {
                Layout.fillWidth: true
                labelColor: theme.textDim
                labelSize: 10
                content: "HUD shell / refresh "
                    + (Plasmoid.configuration.refreshMs || Constants.REFRESH_MS)
                    + "ms / popup ttl "
                    + (Plasmoid.configuration.eventPopupTtlMs || Constants.EVENT_POPUP_TTL_MS)
                    + "ms"
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
