pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "../code/constants.js" as Constants
import "../code/dataSource.js" as DataSource
import "../code/stateAdapter.js" as StateAdapter
import "blocks"
import "common"
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
            dataPath: Constants.DATA_JSON_PATH,
        }, sourceState);
        adaptedState = StateAdapter.adapt(sourceState.data);
    }

    Timer {
        id: refreshTimer
        interval: Constants.REFRESH_MS
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
            }

            CountersBlock {
                Layout.fillWidth: true
                counters: root.adaptedState.counters
            }

            HudPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                accentColor: theme.borderSoft

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: theme.panelPadding
                    spacing: theme.spacingSm

                    MonoLabel {
                        labelColor: theme.textMuted
                        labelSize: 11
                        content: "SNAPSHOT STAGING"
                    }

                    MonoLabel {
                        Layout.fillWidth: true
                        labelColor: theme.text
                        labelSize: 12
                        content: root.sourceState.status === "ready"
                            ? "Primary temp " + (root.adaptedState.snapshot.primaryTemperature.currentC !== null
                                ? root.adaptedState.snapshot.primaryTemperature.currentC + " C"
                                : "n/a")
                            : "Waiting for telemetry feed"
                    }

                    ThinBar {
                        Layout.fillWidth: true
                        value: root.adaptedState.snapshot.primaryTemperature.ratio
                        barColor: root.adaptedState.snapshot.cpu.state === "throttling"
                            ? theme.critical
                            : root.adaptedState.snapshot.cpu.state === "warning"
                                ? theme.warn
                                : theme.ok
                    }

                    MonoLabel {
                        Layout.fillWidth: true
                        labelColor: theme.textDim
                        labelSize: 11
                        content: root.sourceState.status === "degraded"
                            ? "Using last valid snapshot: " + root.sourceState.error
                            : "Blocks will mount below this shell in the next commits."
                    }
                }
            }

            MonoLabel {
                Layout.fillWidth: true
                labelColor: theme.textDim
                labelSize: 10
                content: "HUD shell / refresh " + Constants.REFRESH_MS + "ms / popup ttl " + Constants.EVENT_POPUP_TTL_MS + "ms"
            }
        }
    }
}
