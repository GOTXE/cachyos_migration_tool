pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root

    property color dotColor: "#52ff93"

    implicitWidth: 10
    implicitHeight: 10
    radius: width / 2
    color: dotColor
    border.width: 1
    border.color: Qt.lighter(dotColor, 1.15)
}
