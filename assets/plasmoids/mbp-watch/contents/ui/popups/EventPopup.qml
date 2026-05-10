pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kquickcontrolsaddons as KQuickControlsAddons

import "../common"
import "../theme"

Item {
    id: root

    property var eventData: null
    property int ttlMs: 30000
    property bool shown: eventData !== null

    signal closeRequested()
    signal markReadRequested(var eventData)
    signal dashboardRequested()

    visible: shown
    opacity: shown ? 1 : 0

    Theme {
        id: theme
    }

    KQuickControlsAddons.Clipboard {
        id: clipboard
    }

    Timer {
        id: closeTimer
        interval: root.ttlMs
        repeat: false
        running: root.shown
        onTriggered: root.closeRequested()
    }

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: theme.spacingLg
    height: shown ? 188 : 0

    HudPanel {
        anchors.fill: parent
        raised: true
        accentColor: theme.warn

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: theme.panelPadding
            spacing: theme.spacingSm

            RowLayout {
                Layout.fillWidth: true

                MonoLabel {
                    Layout.fillWidth: true
                    labelColor: theme.warn
                    labelSize: 11
                    content: root.eventData ? String(root.eventData.category || "other").toUpperCase() : "EVENT"
                }

                IconActionButton {
                    label: "CLOSE"
                    accentColor: theme.borderSoft
                    onClicked: root.closeRequested()
                }
            }

            MonoLabel {
                Layout.fillWidth: true
                labelColor: theme.textDim
                labelSize: 10
                content: root.eventData ? String(root.eventData.ts || "") : ""
            }

            MonoLabel {
                Layout.fillWidth: true
                labelColor: theme.text
                labelSize: 12
                content: root.eventData ? String(root.eventData.message || "") : ""
            }

            RowLayout {
                Layout.fillWidth: true

                IconActionButton {
                    label: "COPY"
                    accentColor: theme.borderSoft
                    onClicked: {
                        if (root.eventData) {
                            clipboard.content = "[" + root.eventData.category + "] " + root.eventData.ts + " " + root.eventData.message
                        }
                    }
                }

                IconActionButton {
                    label: "MARK READ"
                    accentColor: theme.warn
                    onClicked: {
                        if (root.eventData) {
                            root.markReadRequested(root.eventData)
                        }
                    }
                }

                IconActionButton {
                    label: "OPEN"
                    accentColor: theme.ok
                    onClicked: root.dashboardRequested()
                }
            }
        }
    }
}
