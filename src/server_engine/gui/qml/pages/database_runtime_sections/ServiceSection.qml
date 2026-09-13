import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components"
as Components
import "../../i18n"

Item {
    id: root
    property
    var pageRoot
    property
    var dashboardBridge
    property
    var runtimeWindow
    property bool runtimeRefreshQueued: false
    property bool actionLocked: false

    function queueRuntimeRefresh() {
        if (runtimeRefreshQueued) {
            return
        }
        runtimeRefreshQueued = true
        runtimeRefreshTimer.restart()
    }

    function lockAction() {
        actionLocked = true
        actionUnlockTimer.restart()
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        Timer {
            id: runtimeRefreshTimer
            interval: 180
            repeat: false
            onTriggered: {
                if (dashboardBridge && dashboardBridge.refreshDatabaseRuntime) {
                    dashboardBridge.refreshDatabaseRuntime()
                }
                root.runtimeRefreshQueued = false
            }
        }

        Component.onCompleted: root.queueRuntimeRefresh()
        onVisibleChanged: {
            if (visible) {
                root.queueRuntimeRefresh()
            }
        }

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
                    color: pageRoot && pageRoot.databaseRunning ? Theme.success : Theme.danger
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Server Status"
                        color: Theme.muted
                        font.pixelSize: 11
                    }
                    Text {
                        text: pageRoot && pageRoot.databaseRunning ? "Running" : "Stopped"
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

                Text {
                    text: "Home"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseRuntimeHome || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    text: "Data dir"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseDataDir || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    text: "Config file"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseConfigPath || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    text: "Log file"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseLogPath || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    text: "Port"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabasePort || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                }

                Text {
                    text: "Version"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseRuntimeLabel || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    text: "Running since"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: pageRoot && pageRoot.databaseRunning
                        ? String(dashboardBridge.activeDatabaseRuntimeStartedAt || "Loading...")
                        : "Not running"
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    text: "Host"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseRuntimeHost || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    text: "Socket"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseRuntimeSocket || "Loading...")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    text: "Databases"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    text: String(dashboardBridge.activeDatabaseCount || 0) + (dashboardBridge.activeDatabaseCount === 1 ? " database" : " databases")
                    color: Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }
            }



            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerRight: Row {
            spacing: 8

            Components.QuickActionButton {
                tooltip: Strings.t("refresh")
                iconSource: "../icons/lucide/rotate-cw.svg"
                enabled: !dashboardBridge.databaseActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.databaseActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    runtimeRefreshQueued = false
                    dashboardBridge.refreshDatabaseRuntime()
                }
            }

            Components.AppButton {
                text: Strings.t("restart")
                enabled: !dashboardBridge.databaseActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.databaseActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.restartDatabaseRuntime()
                }
            }
            
            Components.AppButton {
                visible: !pageRoot.databaseRunning
                text: dashboardBridge.databaseActionBusy ? "Starting..." : "Start"
                highlighted: true
                textColor: "white"
                enabled: !dashboardBridge.databaseActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.databaseActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.startDatabaseRuntime()
                }
            }

            Components.AppButton {
                highlighted: true
                visible: pageRoot.databaseRunning
                text: dashboardBridge.databaseActionBusy ? "Stopping..." : "Stop"
                enabled: !dashboardBridge.databaseActionBusy && !actionLocked
                onClicked: {
                    if (dashboardBridge.databaseActionBusy || actionLocked) {
                        return
                    }
                    lockAction()
                    dashboardBridge.stopDatabaseRuntime()
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

