pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var counters: ({
        wifi: 0,
        connectivity: 0,
        gpu: 0,
        bluetooth: 0,
        thermal: 0,
        pm: 0,
        audio: 0,
        throttle: 0,
        total: 0,
    })

    readonly property var counterRows: [
        { key: "wifi", label: "WI-FI" },
        { key: "connectivity", label: "CONNECTIVITY" },
        { key: "gpu", label: "GPU / DRM" },
        { key: "bluetooth", label: "BLUETOOTH" },
        { key: "thermal", label: "THERMAL / ACPI" },
        { key: "pm", label: "SUSPEND / PM" },
        { key: "audio", label: "AUDIO / HW" },
        { key: "throttle", label: "THROTTLE EVENTS" },
    ]

    Theme {
        id: theme
    }

    implicitHeight: 220
    accentColor: root.counters.total > 0 ? theme.warn : theme.borderSoft

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
                content: "COUNTERS"
            }

            MonoLabel {
                labelColor: root.counters.total > 0 ? theme.warn : theme.ok
                labelSize: 11
                content: "TOTAL " + root.counters.total
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: theme.spacingSm
            columnSpacing: theme.spacingSm

            Repeater {
                model: root.counterRows

                delegate: HudPanel {
                    id: counterCard
                    required property var modelData

                    readonly property int value: root.counters[counterCard.modelData.key] || 0
                    readonly property bool active: counterCard.value > 0

                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    raised: counterCard.active
                    accentColor: counterCard.active ? theme.warn : theme.borderSoft

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: theme.spacingSm
                        spacing: 4

                        MonoLabel {
                            Layout.fillWidth: true
                            labelColor: counterCard.active ? theme.warn : theme.textMuted
                            labelSize: 10
                            content: counterCard.modelData.label
                        }

                        MonoLabel {
                            labelColor: counterCard.active ? theme.warn : theme.ok
                            labelSize: 20
                            content: counterCard.active ? String(counterCard.value) : "0"
                        }

                        ThinBar {
                            Layout.fillWidth: true
                            value: counterCard.active ? Math.min(1, counterCard.value / 5) : 0.08
                            barColor: counterCard.active ? theme.warn : theme.borderSoft
                        }
                    }
                }
            }
        }
    }
}
