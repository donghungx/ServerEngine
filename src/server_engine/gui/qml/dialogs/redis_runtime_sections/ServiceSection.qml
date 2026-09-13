import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle { width: 12; height: 12; radius: 6; color: String(dashboardBridge.activeRedisServiceState || "").toLowerCase() === "running" ? Theme.success : Theme.danger }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Server Status"; color: Theme.muted; font.pixelSize: 11 }
                    Text { text: String(dashboardBridge.activeRedisServiceState || "Stopped"); color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.65 }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                radius: Theme.radius
                color: Theme.surface
                border.color: Theme.border
                border.width: 1
                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
                    Text { text: Strings.t("runtime.home"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.activeRedisRuntimeHome; color: Theme.text; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                    Text { text: Strings.t("data.directory"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.activeRedisDataDir; color: Theme.text; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: dashboardBridge.redisRuntimeMessage
            color: dashboardBridge.redisRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Components.QuickActionButton {
                text: ""
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: Strings.t("refresh")
                onClicked: dashboardBridge.refreshRedisRuntime()
            }

            Components.AppButton {
                text: Strings.t("restart")
                enabled: !dashboardBridge.redisActionBusy
                onClicked: dashboardBridge.restartRedisRuntime()
            }

            Components.AppButton {
                visible: !pageRoot.redisRunning
                text: dashboardBridge.redisActionBusy ? "Starting..." : "Start"
                highlighted: true
                textColor: "white"
                enabled: !dashboardBridge.redisActionBusy
                onClicked: dashboardBridge.startRedisRuntime()
            }
            Components.AppButton {
                visible: pageRoot.redisRunning
                text: dashboardBridge.redisActionBusy ? "Stopping..." : "Stop"
                enabled: !dashboardBridge.redisActionBusy
                onClicked: dashboardBridge.stopRedisRuntime()
            }
        }
    }
}
