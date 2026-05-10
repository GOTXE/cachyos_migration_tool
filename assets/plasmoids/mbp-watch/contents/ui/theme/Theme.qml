pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    readonly property color bg: "#08110c"
    readonly property color panel: "#102018"
    readonly property color panelRaised: "#13271d"
    readonly property color border: "#2f7348"
    readonly property color borderSoft: "#1b4f31"
    readonly property color glow: "#66ff99"
    readonly property color text: "#d7ffe6"
    readonly property color textMuted: "#7ab592"
    readonly property color textDim: "#4f7f5f"
    readonly property color ok: "#52ff93"
    readonly property color warn: "#f4cb68"
    readonly property color critical: "#ff6666"
    readonly property color barBg: "#0b120d"
    readonly property int radiusLg: 18
    readonly property int radiusMd: 12
    readonly property int radiusSm: 8
    readonly property int spacingXs: 6
    readonly property int spacingSm: 10
    readonly property int spacingMd: 14
    readonly property int spacingLg: 18
    readonly property int panelPadding: 14
    readonly property int thinBarHeight: 4
    readonly property string monoFont: "JetBrains Mono Nerd Font"

    function severityColor(className) {
        if (className === "critical") {
            return critical;
        }

        if (className === "warn") {
            return warn;
        }

        return ok;
    }
}
