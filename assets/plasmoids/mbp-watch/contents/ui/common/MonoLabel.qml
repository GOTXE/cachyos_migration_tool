pragma ComponentBehavior: Bound

import QtQuick

import "../theme"

Text {
    id: root

    property string content: ""
    property color labelColor: theme.text
    property int labelSize: 12
    property bool uppercase: false

    Theme {
        id: theme
    }

    color: labelColor
    font.family: theme.monoFont
    font.pixelSize: labelSize
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    renderType: Text.NativeRendering
    text: uppercase ? String(content).toUpperCase() : content
}
