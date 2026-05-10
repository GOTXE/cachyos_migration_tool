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
                    required property var modelData

                    readonly property int value: root.counters[modelData.key] || 0
                    readonly property bool active: value > 0

                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    raised: active
                    accentColor: active ? theme.warn : theme.borderSoft

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: theme.spacingSm
                        spacing: 4

                        MonoLabel {
                            Layout.fillWidth: true
                            labelColor: active ? theme.warn : theme.textMuted
                            labelSize: 10
                            content: modelData.label
                        }

                        MonoLabel {
                            labelColor: active ? theme.warn : theme.ok
                            labelSize: 20
                            content: active ? String(value) : "0"
                        }

                        ThinBar {
                            Layout.fillWidth: true
                            value: active ? Math.min(1, value / 5) : 0.08
                            barColor: active ? theme.warn : theme.borderSoft
                        }
                    }
                }
            }
        }
    }
}
