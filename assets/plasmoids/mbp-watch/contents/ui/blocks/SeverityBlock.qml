pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var severity: ({
        className: "ok",
        title: "Stable",
        text: "",
        reason: "",
    })
    signal dashboardRequested()

    Theme {
        id: theme
    }

    accentColor: theme.severityColor(root.severity.className)

    implicitHeight: 132

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.panelPadding
        spacing: theme.spacingXs

        RowLayout {
            Layout.fillWidth: true

            MonoLabel {
                Layout.fillWidth: true
                labelColor: theme.textMuted
                labelSize: 11
                content: "GLOBAL SEVERITY"
            }

            IconActionButton {
                label: "OPEN"
                accentColor: theme.borderSoft
                onClicked: root.dashboardRequested()
            }
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: theme.severityColor(root.severity.className)
            labelSize: 18
            content: root.severity.title
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: theme.text
            labelSize: 12
            content: root.severity.text
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: theme.textDim
            labelSize: 11
            content: root.severity.reason
        }
    }
}
