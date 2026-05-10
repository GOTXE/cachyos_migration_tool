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
    accentColor: toneColor

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
            labelColor: toneColor
            labelSize: 18
            content: battery.percentage !== null ? battery.percentage + "%" : "n/a"
        }

        MonoLabel {
            labelColor: theme.textDim
            labelSize: 10
            content: battery.state
        }

        ThinBar {
            Layout.fillWidth: true
            value: ratioValue
            barColor: toneColor
        }
    }
}
