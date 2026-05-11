pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var battery: ({
        percentage: null,
        state: "unknown",
        tone: "ok",
    })

    Theme {
        id: theme
    }

    readonly property color toneColor: battery.tone === "critical" ? theme.critical : battery.tone === "warn" ? theme.warn : theme.ok
    readonly property real ratioValue: battery.percentage !== null ? Math.max(0, Math.min(1, battery.percentage / 100)) : 0.1

    implicitHeight: 104
    accentColor: root.toneColor

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        spacing: theme.spacingXs

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 10
            content: "BATTERY"
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: root.toneColor
            labelSize: 18
            maxLines: 1
            content: root.battery.percentage !== null ? root.battery.percentage + "%" : "n/a"
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: theme.textDim
            labelSize: 10
            maxLines: 1
            content: root.battery.state
        }

        ThinBar {
            Layout.fillWidth: true
            value: root.ratioValue
            barColor: root.toneColor
        }
    }
}
