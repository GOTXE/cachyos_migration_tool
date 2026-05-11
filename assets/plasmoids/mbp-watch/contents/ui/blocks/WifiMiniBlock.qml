pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root

    property var wifi: ({
        connected: false,
        ssid: "",
        signalDbm: null,
        latencyMs: null,
        tone: "ok",
    })

    Theme {
        id: theme
    }

    readonly property color toneColor: wifi.tone === "critical" ? theme.critical : wifi.tone === "warn" ? theme.warn : theme.ok
    readonly property real signalValue: wifi.signalDbm !== null ? Math.max(0.08, Math.min(1, (wifi.signalDbm + 90) / 55)) : 0.08

    implicitHeight: 104
    accentColor: root.toneColor

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        spacing: theme.spacingXs

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 10
            content: "WI-FI"
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: root.toneColor
            labelSize: 15
            maxLines: 1
            content: root.wifi.connected ? (root.wifi.ssid ? root.wifi.ssid : "connected") : "disconnected"
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: theme.textDim
            labelSize: 10
            maxLines: 1
            content: root.wifi.signalDbm !== null
                ? root.wifi.signalDbm + " dBm / " + (root.wifi.latencyMs !== null ? root.wifi.latencyMs + " ms" : "n/a")
                : "signal unavailable"
        }

        ThinBar {
            Layout.fillWidth: true
            value: root.signalValue
            barColor: root.toneColor
        }
    }
}
