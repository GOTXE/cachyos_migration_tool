pragma ComponentBehavior: Bound

import QtQuick

import "../theme"

Rectangle {
    id: root

    property bool raised: false
    property color accentColor: theme.border

    Theme {
        id: theme
    }

    radius: theme.radiusMd
    color: raised ? theme.panelRaised : theme.panel
    border.width: 1
    border.color: accentColor
    opacity: 0.92

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Qt.rgba(theme.glow.r, theme.glow.g, theme.glow.b, 0.35)
    }
}
