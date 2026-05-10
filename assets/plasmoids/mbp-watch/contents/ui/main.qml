pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "../code/constants.js" as Constants
import "../code/dataSource.js" as DataSource

PlasmoidItem {
    id: root

    property var sourceState: ({
        status: "loading",
        data: null,
        lastValidData: null,
        error: "",
        loadedAt: "",
    })

    implicitWidth: 360
    implicitHeight: 720

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.title: "MBP Watch"
    Plasmoid.icon: "utilities-system-monitor"

    function refreshData() {
        sourceState = DataSource.readState({
            dataPath: Constants.DATA_JSON_PATH,
        }, sourceState);
    }

    Timer {
        id: refreshTimer
        interval: Constants.REFRESH_MS
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshData()
    }

    fullRepresentation: Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "#141b16"
            opacity: 0.88
            border.width: 1
            border.color: "#3cff7a"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            Text {
                text: "MBP Watch"
                color: "#d7ffe6"
                font.pixelSize: 20
                font.bold: true
            }

            Text {
                text: "Scaffold Plasma 6 listo. Refresco seguro de data.json activado."
                color: "#8ed8a8"
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                Layout.fillWidth: true
            }

            Text {
                text: "State: " + root.sourceState.status
                color: root.sourceState.status === "ready" ? "#52ff93" : "#d3b063"
                font.pixelSize: 13
            }

            Text {
                text: root.sourceState.data && root.sourceState.data.generated
                    ? "Generated: " + root.sourceState.data.generated
                    : "Generated: unavailable"
                color: "#8ed8a8"
                font.pixelSize: 12
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: "#0b120d"
                border.width: 1
                border.color: "#1d5d33"

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.sourceState.status === "ready"
                        ? "data.json loaded from\n" + Constants.DATA_JSON_PATH
                        : root.sourceState.status === "degraded"
                            ? "Using last valid snapshot.\n" + root.sourceState.error
                            : "Waiting for data.json\n" + Constants.DATA_JSON_PATH
                    color: root.sourceState.status === "ready" ? "#7be69f" : "#4f7f5f"
                    font.pixelSize: 14
                }
            }
        }
    }
}
