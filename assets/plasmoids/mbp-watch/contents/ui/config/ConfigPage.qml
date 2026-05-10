pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Pane {
    id: root

    property alias cfg_dataPath: dataPathField.text
    property alias cfg_dashboardUrl: dashboardUrlField.text
    property alias cfg_refreshMs: refreshMsField.value
    property alias cfg_eventPopupTtlMs: popupTtlField.value

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Label {
            text: "MBP Watch"
            font.bold: true
        }

        TextField {
            id: dataPathField
            Layout.fillWidth: true
            placeholderText: "/var/lib/mbp-watch/data.json"
        }

        TextField {
            id: dashboardUrlField
            Layout.fillWidth: true
            placeholderText: "http://127.0.0.1:7070/report.html"
        }

        SpinBox {
            id: refreshMsField
            from: 1000
            to: 60000
            stepSize: 500
        }

        SpinBox {
            id: popupTtlField
            from: 5000
            to: 60000
            stepSize: 1000
        }
    }
}
