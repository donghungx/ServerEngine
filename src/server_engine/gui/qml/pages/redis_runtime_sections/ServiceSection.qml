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
    property bool actionLocked: false

    function lockAction() {
        actionLocked = true
        actionUnlockTimer.restart()
    }

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
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: String(dashboardBridge.activeRedisServiceState || "").toLowerCase() === "running" ? Theme.success : Theme.danger
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Server Status"; color: Theme.muted; font.pixelSize: 11 }
                    Text { text: String(dashboardBridge.activeRedisServiceState || "Stopped"); color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.65 }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 18
                rowSpacing: 8
                Text { text: "Runtime"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeRedisRuntimeLabel || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Home"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeRedisRuntimeHome || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Data dir"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeRedisDataDir || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Port"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeRedisPort || "-"); color: Theme.muted; font.pixelSize: 13 }
                Text { text: "Persistence"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: dashboardBridge.redisGeneralAppendOnlyDraft ? "Append-only enabled" : "Snapshot mode"; color: Theme.muted; font.pixelSize: 13 }
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
                enabled: !dashboardBridge.redisActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.redisActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.refreshRedisRuntime()
                }
            }

            Components.AppButton {
                text: Strings.t("restart")
                enabled: !dashboardBridge.redisActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.redisActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.restartRedisRuntime()
                }
            }

            Components.AppButton {
                visible: !pageRoot.redisRunning
                text: dashboardBridge.redisActionBusy ? "Starting..." : "Start"
                highlighted: true
                textColor: "white"
                enabled: !dashboardBridge.redisActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.redisActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.startRedisRuntime()
                }
            }
            Components.AppButton {
                visible: pageRoot.redisRunning
                text: dashboardBridge.redisActionBusy ? "Stopping..." : "Stop"
                highlighted: true
                textColor: "white"
                enabled: !dashboardBridge.redisActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.redisActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.stopRedisRuntime()
                }
            }
        }
    }

    Timer {
        id: actionUnlockTimer
        interval: 1200
        repeat: false
        onTriggered: actionLocked = false
    }
}
