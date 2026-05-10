pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var loadAndSystem: ({
        loadAverage: "",
        contextSwitches: 0,
    })

    Theme {
        id: theme
    }

    implicitHeight: 104
    accentColor: theme.borderSoft

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        spacing: theme.spacingXs

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 10
            content: "SYSTEM LOAD"
        }

        MonoLabel {
            labelColor: theme.text
            labelSize: 16
            content: loadAndSystem.loadAverage ? loadAndSystem.loadAverage : "n/a"
        }

        MonoLabel {
            labelColor: theme.textDim
            labelSize: 10
            content: "ctx " + loadAndSystem.contextSwitches
        }

        ThinBar {
            Layout.fillWidth: true
            value: 0.35
            barColor: theme.borderSoft
        }
    }
}
