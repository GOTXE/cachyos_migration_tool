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
    height: shown ? Math.max(224, popupPanel.implicitHeight) : 0

    HudPanel {
        id: popupPanel
        anchors.fill: parent
        raised: true
        accentColor: theme.warn
        implicitHeight: popupContent.implicitHeight + (theme.panelPadding * 2)

        ColumnLayout {
            id: popupContent
            anchors.fill: parent
            anchors.margins: theme.panelPadding
            spacing: theme.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 2

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
                lineHeightPx: 14
                allowWrap: true
                maxLines: 2
                content: root.eventData ? String(root.eventData.ts || "") : ""
            }

            MonoLabel {
                Layout.fillWidth: true
                labelColor: theme.text
                labelSize: 12
                lineHeightPx: 18
                allowWrap: true
                maxLines: 4
                content: root.eventData ? String(root.eventData.message || "") : ""
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                columns: 3
                rowSpacing: theme.spacingSm
                columnSpacing: theme.spacingSm

                IconActionButton {
                    Layout.fillWidth: true
                    label: "COPY"
                    accentColor: theme.borderSoft
                    onClicked: {
                        if (root.eventData) {
                            clipboard.content = "[" + root.eventData.category + "] " + root.eventData.ts + " " + root.eventData.message
                        }
                    }
                }

                IconActionButton {
                    Layout.fillWidth: true
                    label: "MARK READ"
                    accentColor: theme.warn
                    onClicked: {
                        if (root.eventData) {
                            root.markReadRequested(root.eventData)
                        }
                    }
                }

                IconActionButton {
                    Layout.fillWidth: true
                    label: "OPEN"
                    accentColor: theme.ok
                    onClicked: root.dashboardRequested()
                }
            }
        }
    }
}
