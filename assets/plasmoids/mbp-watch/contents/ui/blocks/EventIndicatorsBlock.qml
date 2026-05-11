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

    implicitHeight: 124
    accentColor: indicators.length > 0 ? theme.warn : theme.borderSoft

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.panelPadding
        spacing: theme.spacingMd

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 11
            content: "RECENT EVENTS"
        }

        Flow {
            id: indicatorsFlow
            Layout.fillWidth: true
            spacing: theme.spacingSm

            Repeater {
                model: root.indicators

                delegate: Rectangle {
                    id: indicatorCard
                    required property var modelData

                    width: 112
                    height: 58
                    radius: theme.radiusSm
                    color: Qt.rgba(theme.panelRaised.r, theme.panelRaised.g, theme.panelRaised.b, 0.95)
                    border.width: 1
                    border.color: modelData.unread > 0 ? theme.warn : theme.borderSoft

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        MonoLabel {
                            labelColor: indicatorCard.modelData.unread > 0 ? theme.warn : theme.textMuted
                            labelSize: 10
                            lineHeightPx: 14
                            content: String(indicatorCard.modelData.category || "other").toUpperCase()
                        }

                        MonoLabel {
                            labelColor: indicatorCard.modelData.unread > 0 ? theme.text : theme.textDim
                            labelSize: 12
                            lineHeightPx: 16
                            content: indicatorCard.modelData.unread > 0
                                ? indicatorCard.modelData.unread + " unread"
                                : indicatorCard.modelData.total + " seen"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (indicatorCard.modelData.latestEvent) {
                                root.eventActivated(indicatorCard.modelData.latestEvent)
                            }
                        }
                    }
                }
            }
        }
    }
}
