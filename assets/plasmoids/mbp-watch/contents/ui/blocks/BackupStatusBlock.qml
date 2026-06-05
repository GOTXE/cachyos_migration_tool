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

    implicitHeight: 72
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

            MonoLabel {
                labelColor: root.statusColor
                labelSize: 11
                content: root.statusIcon + " " + root.statusText
                Layout.preferredWidth: 48
            }

            MonoLabel {
                labelColor: theme.textDim
                labelSize: 11
                content: root.backup.snapshot_count + " snapshots"
                Layout.preferredWidth: 88
            }

            MonoLabel {
                labelColor: theme.textDim
                labelSize: 11
                content: root.backup.total_size_gb.toFixed(1) + " GiB"
                Layout.preferredWidth: 60
            }

            MonoLabel {
                labelColor: theme.textDim
                labelSize: 11
                content: root.backup.last_snapshot_time ? root.backup.last_snapshot_time.split("T")[1].slice(0, 5) : "n/a"
                Layout.preferredWidth: 42
            }
        }

        MonoLabel {
            Layout.fillWidth: true
            labelColor: root.backup.error ? theme.critical : theme.ok
            labelSize: 9
            maxLines: 1
            horizontalAlignment: Text.AlignHCenter
            content: root.backup.error ? "ERROR: " + root.backup.error : "Last: " + (root.backup.last_snapshot_id || "n/a")
        }

        ThinBar {
            Layout.fillWidth: true
            value: root.backup.status === "ok" ? 1.0 : root.backup.status === "stale" ? 0.5 : root.backup.status === "pending" ? 0.3 : 0.0
            barColor: root.statusColor
        }
    }
}
