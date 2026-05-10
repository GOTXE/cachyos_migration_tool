pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var cpu: ({
        state: "normal",
        freqRatio: null,
        headroom: null,
        governor: "unknown",
        energyMode: "unknown",
    })

    Theme {
        id: theme
    }

    readonly property color tone: cpu.state === "throttling" ? theme.critical : cpu.state === "warning" ? theme.warn : theme.ok
    readonly property real ratioValue: cpu.freqRatio !== null ? Math.max(0, Math.min(1, cpu.freqRatio / 100)) : 0.1

    implicitHeight: 104
    accentColor: tone

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        spacing: theme.spacingXs

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 10
            content: "CPU"
        }

        MonoLabel {
            labelColor: root.tone
            labelSize: 16
            content: cpu.freqRatio !== null ? cpu.freqRatio + "%" : cpu.state
        }

        MonoLabel {
            labelColor: theme.textDim
            labelSize: 10
            content: cpu.governor + " / " + cpu.energyMode
        }

        ThinBar {
            Layout.fillWidth: true
            value: ratioValue
            barColor: root.tone
        }
    }
}
