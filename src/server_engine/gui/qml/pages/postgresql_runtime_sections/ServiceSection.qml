import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot: ({})
    property var dashboardBridge: ({})
    property var runtimeWindow

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (pageRoot && pageRoot.dashboardBridge) {
            return pageRoot.dashboardBridge
        }
        return ({})
    }

    property bool actionLocked: false

    function lockAction() {
        actionLocked = true
        actionUnlockTimer.restart()
    }

    function unlockAction() {
        actionLocked = false
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
                    color: String(bridge().activePostgresqlServiceState || "").toLowerCase() === "running" ? Theme.success : Theme.danger
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Server Status"; color: Theme.muted; font.pixelSize: 11 }
                    Text {
                        text: String(bridge().activePostgresqlServiceState || "Stopped")
                        color: Theme.text
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
                opacity: 0.65
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 18
                rowSpacing: 8
                Text { text: "Runtime"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(bridge().activePostgresqlRuntimeLabel || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Home"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(bridge().activePostgresqlRuntimeHome || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Data dir"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(bridge().activePostgresqlDataDir || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Port"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(bridge().activePostgresqlPort || "-"); color: Theme.muted; font.pixelSize: 13 }
                Text { text: "Host"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(bridge().activePostgresqlHost || "127.0.0.1"); color: Theme.muted; font.pixelSize: 13 }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: String(bridge().postgresqlRuntimeMessage || "")
            color: bridge().postgresqlRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            width: parent.width
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 8

            Components.QuickActionButton {
                text: ""
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: Strings.t("refresh")
                onClicked: bridge().refreshPostgresqlRuntime && bridge().refreshPostgresqlRuntime()
            }

            Components.AppButton {
                text: Strings.t("restart")
                enabled: !bridge().postgresqlActionBusy && !actionLocked
                onClicked: {
                    if (bridge().postgresqlActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    bridge().restartPostgresqlRuntime && bridge().restartPostgresqlRuntime()
                }
            }

            Components.AppButton {
                visible: !pageRoot.postgresqlRunning
                text: bridge().postgresqlActionBusy ? "Starting..." : "Start"
                textColor: "white"
                enabled: !bridge().postgresqlActionBusy && !actionLocked
                onClicked: {
                    if (bridge().postgresqlActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    bridge().startPostgresqlRuntime && bridge().startPostgresqlRuntime()
                }
                highlighted: true
            }

            Components.AppButton {
                visible: pageRoot.postgresqlRunning
                text: bridge().postgresqlActionBusy ? "Stopping..." : "Stop"
                enabled: !bridge().postgresqlActionBusy && !actionLocked
                onClicked: {
                    if (bridge().postgresqlActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    bridge().stopPostgresqlRuntime && bridge().stopPostgresqlRuntime()
                }
                highlighted: true
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
