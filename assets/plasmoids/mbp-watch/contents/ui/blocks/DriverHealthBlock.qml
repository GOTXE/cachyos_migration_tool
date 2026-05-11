pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var driverHealth: ({
        captured: "",
        drivers: [],
    })

    Theme {
        id: theme
    }

    implicitHeight: 180
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
                content: "DRIVER HEALTH"
            }

            MonoLabel {
                labelColor: theme.textDim
                labelSize: 10
                content: root.driverHealth.captured ? root.driverHealth.captured : "pending"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: theme.spacingXs

            Repeater {
                model: root.driverHealth.drivers.slice(0, 4)

                delegate: Rectangle {
                    id: driverEntry
                    required property var modelData

                    readonly property color tone: driverEntry.modelData.status === "ERROR"
                        ? theme.critical
                        : driverEntry.modelData.status === "WARN"
                            ? theme.warn
                            : theme.ok

                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: theme.radiusSm
                    color: Qt.rgba(theme.panelRaised.r, theme.panelRaised.g, theme.panelRaised.b, 0.92)
                    border.width: 1
                    border.color: tone

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        StatusDot {
                            dotColor: driverEntry.tone
                        }

                        MonoLabel {
                            Layout.preferredWidth: 92
                            labelColor: theme.text
                            labelSize: 10
                            content: driverEntry.modelData.name
                        }

                        MonoLabel {
                            Layout.fillWidth: true
                            labelColor: theme.textDim
                            labelSize: 10
                            content: driverEntry.modelData.detail ? driverEntry.modelData.detail : driverEntry.modelData.status
                        }
                    }
                }
            }
        }
    }
}
