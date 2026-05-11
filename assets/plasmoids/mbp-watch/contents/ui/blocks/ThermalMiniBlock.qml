pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var thermal: ({
        primaryTemperature: {
            label: "CPU Package",
            currentC: null,
            ratio: 0,
        },
        fan: {
            text: "",
            rpm: null,
        },
    })

    Theme {
        id: theme
    }

    readonly property real valueRatio: thermal.primaryTemperature.ratio || 0
    readonly property color tone: valueRatio >= 0.85 ? theme.critical : valueRatio >= 0.7 ? theme.warn : theme.ok

    implicitHeight: 104
    accentColor: tone

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        spacing: theme.spacingXs

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 10
            content: "THERMAL"
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: root.tone
            labelSize: 18
            maxLines: 1
            content: root.thermal.primaryTemperature.currentC !== null
                ? root.thermal.primaryTemperature.currentC + " C"
                : "n/a"
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: theme.textDim
            labelSize: 10
            maxLines: 1
            content: root.thermal.fan.text ? root.thermal.fan.text : root.thermal.primaryTemperature.label
        }

        ThinBar {
            Layout.fillWidth: true
            value: root.valueRatio
            barColor: root.tone
        }
    }
}
