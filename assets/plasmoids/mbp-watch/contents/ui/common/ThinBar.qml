pragma ComponentBehavior: Bound

import QtQuick

import "../theme"

Item {
    id: root

    property real value: 0
    property color barColor: theme.ok

    Theme {
        id: theme
    }

    implicitHeight: theme.thinBarHeight
    implicitWidth: 120

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: theme.barBg
        border.width: 1
        border.color: theme.borderSoft
    }

    Rectangle {
        width: Math.max(0, Math.min(root.width, root.width * root.value))
        height: parent.height
        radius: height / 2
        color: root.barColor
    }
}
