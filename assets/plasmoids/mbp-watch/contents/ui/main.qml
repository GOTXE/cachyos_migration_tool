pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    implicitWidth: 360
    implicitHeight: 720

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.title: "MBP Watch"
    Plasmoid.icon: "utilities-system-monitor"

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
                text: "Scaffold Plasma 6 listo para implementar la v1."
                color: "#8ed8a8"
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                Layout.fillWidth: true
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
                    text: "Waiting for data.json"
                    color: "#4f7f5f"
                    font.pixelSize: 14
                }
            }
        }
    }
}
