pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var dailyHistory: []

    Theme {
        id: theme
    }

    function maxTotal() {
        var max = 1;

        for (var i = 0; i < dailyHistory.length; i += 1) {
            if ((dailyHistory[i].total || 0) > max) {
                max = dailyHistory[i].total;
            }
        }

        return max;
    }

    implicitHeight: 170
    accentColor: theme.borderSoft

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.panelPadding
        spacing: theme.spacingSm

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 11
            content: "DAILY HISTORY"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: theme.spacingXs

            Repeater {
                model: root.dailyHistory

                delegate: Item {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 110

                    Column {
                        anchors.fill: parent
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 82

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(16, parent.width - 6)
                                height: Math.max(8, ((modelData.total || 0) / root.maxTotal()) * 82)
                                radius: 6
                                color: (modelData.total || 0) > 0 ? theme.warn : theme.borderSoft
                                border.width: 1
                                border.color: (modelData.total || 0) > 0 ? theme.warn : theme.borderSoft
                            }
                        }

                        MonoLabel {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            labelColor: theme.textDim
                            labelSize: 9
                            content: modelData.date ? modelData.date.slice(5) : "--"
                        }
                    }
                }
            }
        }
    }
}
