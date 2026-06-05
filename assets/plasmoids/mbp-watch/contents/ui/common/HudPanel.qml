pragma ComponentBehavior: Bound

import QtQuick

import "../theme"

Rectangle {
    id: root

    property bool raised: false
    property bool showFrame: true
    property color accentColor: theme.border

    Theme {
        id: theme
    }

    radius: theme.radiusMd
    color: raised ? theme.panelRaised : theme.panel
    border.width: showFrame ? 1 : 0
    border.color: showFrame ? accentColor : "transparent"
    opacity: 0.92

    Rectangle {
        visible: root.showFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Qt.rgba(theme.glow.r, theme.glow.g, theme.glow.b, 0.35)
    }
}
