pragma ComponentBehavior: Bound

import QtQuick

import "../theme"

Text {
    id: root

    property string content: ""
    property color labelColor: theme.text
    property int labelSize: 12
    property bool uppercase: false
    property int lineHeightPx: Math.round(labelSize * 1.35)
    property bool allowWrap: false
    property int maxLines: 1

    Theme {
        id: theme
    }

    clip: true
    color: labelColor
    font.family: theme.monoFont
    font.pixelSize: labelSize
    lineHeightMode: Text.FixedHeight
    lineHeight: lineHeightPx
    textFormat: Text.PlainText
    wrapMode: allowWrap ? Text.WordWrap : Text.NoWrap
    elide: Text.ElideRight
    maximumLineCount: Math.max(1, maxLines)
    renderType: Text.NativeRendering
    text: uppercase ? String(content).toUpperCase() : content
}
