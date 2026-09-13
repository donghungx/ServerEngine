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
                Rectangle { width: 12; height: 12; radius: 6; color: runtimeWindow.webRunning ? Theme.success : Theme.danger }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Server Status"; color: Theme.muted; font.pixelSize: 11 }
                    Text { text: runtimeWindow.webRunning ? "Running" : "Stopped"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.65 }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 18
                rowSpacing: 8

                Text { text: "Web server"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: dashboardBridge.currentWebServerLabel; color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }

                Text { text: "Status"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: runtimeWindow.webRunning ? "Running" : "Stopped"; color: Theme.muted; font.pixelSize: 13 }

                Text { text: "Port"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(pageRoot.apachePortDraft || dashboardBridge.settingsWebPort || "8080"); color: Theme.muted; font.pixelSize: 13 }

                Text { text: "Error log"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.apacheRuntimeLogPath || pageRoot.apacheErrorLogPathDraft || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
            }

            Item { Layout.fillWidth: true; Layout.fillHeight: true }
        }

        footerLeft: Text {
            text: dashboardBridge.stackFeedbackMessage
            color: dashboardBridge.stackFeedbackError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Components.QuickActionButton {
                text: ""
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: Strings.t("reload")
                enabled: !dashboardBridge.stackActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.stackActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.reloadWebRoutes()
                }
            }

            Components.AppButton {
                text: Strings.t("restart")
                enabled: !runtimeWindow.webBusy && !actionLocked
                onClicked: {
                    if (runtimeWindow.webBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.restartWebServerRuntime()
                }
            }

            Components.AppButton {
                text: runtimeWindow.webRunning ? Strings.t("stop") : Strings.t("start")
                highlighted: true
                textColor: "white"
                enabled: !runtimeWindow.webBusy && !actionLocked
                onClicked: {
                    if (runtimeWindow.webBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    runtimeWindow.webRunning
                        ? dashboardBridge.stopWebServerRuntime()
                        : dashboardBridge.startWebServerRuntime()
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
