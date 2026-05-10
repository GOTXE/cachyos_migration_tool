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
    accentColor: toneColor

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
            labelColor: toneColor
            labelSize: 15
            content: wifi.connected ? (wifi.ssid ? wifi.ssid : "connected") : "disconnected"
        }

        MonoLabel {
            labelColor: theme.textDim
            labelSize: 10
            content: wifi.signalDbm !== null
                ? wifi.signalDbm + " dBm / " + (wifi.latencyMs !== null ? wifi.latencyMs + " ms" : "n/a")
                : "signal unavailable"
        }

        ThinBar {
            Layout.fillWidth: true
            value: signalValue
            barColor: toneColor
        }
    }
}
