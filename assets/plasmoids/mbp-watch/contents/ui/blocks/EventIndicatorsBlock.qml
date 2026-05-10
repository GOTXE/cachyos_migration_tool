pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var indicators: []
    signal eventActivated(var eventData)

    Theme {
        id: theme
    }

    implicitHeight: 104
    accentColor: indicators.length > 0 ? theme.warn : theme.borderSoft

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.panelPadding
        spacing: theme.spacingSm

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 11
            content: "RECENT EVENTS"
        }

        Flow {
            Layout.fillWidth: true
            width: parent.width
            spacing: theme.spacingSm

            Repeater {
                model: root.indicators

                delegate: Rectangle {
                    required property var modelData

                    width: 100
                    height: 48
                    radius: theme.radiusSm
                    color: Qt.rgba(theme.panelRaised.r, theme.panelRaised.g, theme.panelRaised.b, 0.95)
                    border.width: 1
                    border.color: modelData.unread > 0 ? theme.warn : theme.borderSoft

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        MonoLabel {
                            labelColor: modelData.unread > 0 ? theme.warn : theme.textMuted
                            labelSize: 10
                            content: String(modelData.category || "other").toUpperCase()
                        }

                        MonoLabel {
                            labelColor: modelData.unread > 0 ? theme.text : theme.textDim
                            labelSize: 12
                            content: modelData.unread > 0
                                ? modelData.unread + " unread"
                                : modelData.total + " seen"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.latestEvent) {
                                root.eventActivated(modelData.latestEvent)
                            }
                        }
                    }
                }
            }
        }
    }
}
