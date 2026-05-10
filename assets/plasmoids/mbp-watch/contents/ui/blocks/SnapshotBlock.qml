pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var snapshot: ({
        primaryTemperature: {},
        fan: {},
        cpu: {},
        battery: {},
        wifi: {},
        loadAndSystem: {},
    })

    Theme {
        id: theme
    }

    implicitHeight: 290
    accentColor: theme.borderSoft

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.panelPadding
        spacing: theme.spacingSm

        RowLayout {
            Layout.fillWidth: true

            MonoLabel {
                Layout.fillWidth: true
                labelColor: theme.textMuted
                labelSize: 11
                content: "SNAPSHOT"
            }

            MonoLabel {
                labelColor: theme.textDim
                labelSize: 10
                content: snapshot.captured ? snapshot.captured : "live"
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: theme.spacingSm
            columnSpacing: theme.spacingSm

            ThermalMiniBlock {
                Layout.fillWidth: true
                thermal: ({
                    primaryTemperature: root.snapshot.primaryTemperature,
                    fan: root.snapshot.fan,
                })
            }

            CpuMiniBlock {
                Layout.fillWidth: true
                cpu: root.snapshot.cpu
            }

            BatteryMiniBlock {
                Layout.fillWidth: true
                battery: root.snapshot.battery
            }

            WifiMiniBlock {
                Layout.fillWidth: true
                wifi: root.snapshot.wifi
            }

            SystemLoadMiniBlock {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                loadAndSystem: root.snapshot.loadAndSystem
            }
        }
    }
}
