pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "../common"
import "../theme"

HudPanel {
    id: root
    showFrame: false

    property var backup: ({
        status: "fail",
        snapshot_count: 0,
        total_size_gb: 0,
        last_snapshot_time: "",
        last_snapshot_id: "",
        error: "",
        server: "",
        server_status: "fail",
    })

    Theme {
        id: theme
    }

    readonly property color statusColor: {
        switch (root.backup.status) {
            case "ok":
                return theme.ok
            case "stale":
                return theme.warn
            case "pending":
                return theme.textMuted
            case "fail":
            default:
                return theme.critical
        }
    }

    readonly property color serverColor: {
        switch (root.backup.server_status) {
            case "ok":
                return theme.ok
            default:
                return theme.critical
        }
    }

    readonly property string statusIcon: {
        switch (root.backup.status) {
            case "ok":
                return "✓"
            case "stale":
                return "⚠"
            case "pending":
                return "⟳"
            case "fail":
            default:
                return "✗"
        }
    }

    readonly property string statusText: {
        switch (root.backup.status) {
            case "ok":
                return "OK"
            case "stale":
                return "STALE"
            case "pending":
                return "PENDING"
            case "fail":
            default:
                return "FAIL"
        }
    }

    readonly property string serverLabel: {
        if (root.backup.server === "LAN") {
            return "LAN"
        }

        if (root.backup.server === "Internet") {
            return "Internet"
        }

        return "n/a"
    }

    readonly property string serverText: {
        if (!root.backup.server) {
            return "SERVER n/a"
        }

        return "SERVER " + root.backup.server.toUpperCase()
    }

    implicitHeight: 112
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        spacing: theme.spacingXs

        MonoLabel {
            labelColor: theme.textMuted
            labelSize: 10
            content: "BACKUP"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: theme.spacingSm

            ColumnLayout {
                Layout.preferredWidth: 64
                Layout.alignment: Qt.AlignTop
                spacing: 2

                MonoLabel {
                    labelColor: root.statusColor
                    labelSize: 12
                    content: root.statusIcon + " " + root.statusText
                }

                MonoLabel {
                    labelColor: theme.textDim
                    labelSize: 11
                    content: root.backup.last_snapshot_time ? root.backup.last_snapshot_time.split("T")[1].slice(0, 5) : "n/a"
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 96
                Layout.alignment: Qt.AlignTop
                spacing: 2

                MonoLabel {
                    labelColor: root.serverColor
                    labelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    content: root.serverText
                }

                MonoLabel {
                    labelColor: theme.textDim
                    labelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    content: root.serverLabel
                }
            }

            MonoLabel {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                labelColor: root.backup.error ? theme.critical : theme.ok
                labelSize: 9
                maxLines: 1
                horizontalAlignment: Text.AlignHCenter
                content: root.backup.error ? "ERROR: " + root.backup.error : "Last: " + (root.backup.last_snapshot_id || "n/a")
            }

            ColumnLayout {
                Layout.preferredWidth: 92
                Layout.alignment: Qt.AlignTop
                spacing: 2

                MonoLabel {
                    labelColor: theme.textDim
                    labelSize: 12
                    horizontalAlignment: Text.AlignRight
                    content: root.backup.snapshot_count + " snapshots"
                }

                MonoLabel {
                    labelColor: theme.textDim
                    labelSize: 11
                    horizontalAlignment: Text.AlignRight
                    content: root.backup.total_size_gb.toFixed(1) + " GiB"
                }
            }
        }

        ThinBar {
            Layout.fillWidth: true
            value: root.backup.status === "ok" ? 1.0 : root.backup.status === "stale" ? 0.5 : root.backup.status === "pending" ? 0.3 : 0.0
            barColor: root.statusColor
        }

        ThinBar {
            Layout.fillWidth: true
            value: root.backup.server_status === "ok" ? 1.0 : 0.0
            barColor: root.serverColor
        }
    }
}
