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
    property bool actionLocked: false

    function lockAction() {
        actionLocked = true
        actionUnlockTimer.restart()
    }

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (pageRoot && pageRoot.dashboardBridge) {
            return pageRoot.dashboardBridge
        }
        return ({})
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
                    color: String(bridge().activeMongodbServiceState || "").toLowerCase() === "running" ? Theme.success : Theme.danger
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Server Status"; color: Theme.muted; font.pixelSize: 11 }
                    Text {
                        text: String(bridge().activeMongodbServiceState || "Stopped")
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
                Text { text: String(bridge().activeMongodbRuntimeLabel || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Home"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(pageRoot.mongodbRuntimeHomeText || bridge().activeMongodbRuntimeHome || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Data dir"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(pageRoot.mongodbRuntimeDataDirText || bridge().activeMongodbDataDir || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Port"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(bridge().activeMongodbPort || "-"); color: Theme.muted; font.pixelSize: 13 }
                Text { text: "Host"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(bridge().activeMongodbHost || "127.0.0.1"); color: Theme.muted; font.pixelSize: 13 }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: String(bridge().mongodbRuntimeMessage || "")
            color: bridge().mongodbRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            width: parent.width
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                visible: !pageRoot.mongodbRunning
                text: bridge().mongodbActionBusy ? "Starting..." : "Start"
                highlighted: true
                textColor: "white"
                enabled: !bridge().mongodbActionBusy && !actionLocked
                onClicked: {
                    if (bridge().mongodbActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    bridge().startMongodbRuntime && bridge().startMongodbRuntime()
                }
            }

            Components.AppButton {
                visible: pageRoot.mongodbRunning
                text: bridge().mongodbActionBusy ? "Stopping..." : "Stop"
                enabled: !bridge().mongodbActionBusy && !actionLocked
                onClicked: {
                    if (bridge().mongodbActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    bridge().stopMongodbRuntime && bridge().stopMongodbRuntime()
                }
            }

            Components.AppButton {
                text: Strings.t("restart")
                enabled: !bridge().mongodbActionBusy && !actionLocked
                onClicked: {
                    if (bridge().mongodbActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    bridge().restartMongodbRuntime && bridge().restartMongodbRuntime()
                }
            }

            Components.QuickActionButton {
                text: ""
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: Strings.t("refresh")
                onClicked: bridge().refreshMongodbRuntime && bridge().refreshMongodbRuntime()
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
