pragma ComponentBehavior: Bound

import QtQuick

import "../theme"

Rectangle {
    id: root

    signal clicked()

    property string label: ""
    property color accentColor: theme.border

    Theme {
        id: theme
    }

    implicitHeight: 28
    implicitWidth: Math.max(78, labelText.implicitWidth + 18)
    radius: theme.radiusSm
    color: buttonArea.pressed ? Qt.rgba(theme.panelRaised.r, theme.panelRaised.g, theme.panelRaised.b, 0.95) : Qt.rgba(theme.panel.r, theme.panel.g, theme.panel.b, 0.9)
    border.width: 1
    border.color: root.accentColor

    Text {
        id: labelText
        anchors.centerIn: parent
        color: theme.text
        font.family: theme.monoFont
        font.pixelSize: 11
        font.bold: true
        text: root.label
    }

    MouseArea {
        id: buttonArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
