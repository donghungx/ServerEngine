import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    property string portDraft: ""
    property string loadedPort: ""
    property string feedbackText: ""
    property bool feedbackError: false

    function loadPort() {
        if (!dashboardBridge) {
            return
        }
        var current = String(dashboardBridge.activeDatabasePort || "")
        if (current.length === 0) {
            current = String(dashboardBridge.settingsDatabasePort || "")
        }
        loadedPort = current
        portDraft = current
        portField.text = current
    }

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    Component.onCompleted: loadPort()
    onDashboardBridgeChanged: loadPort()

    Connections {
        target: mainWindow()
        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "database.restart_after_port_save") {
                if (dashboardBridge && dashboardBridge.restartDatabaseRuntime) {
                    dashboardBridge.restartDatabaseRuntime()
                }
            }
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Components.SettingsLabeledControl {
                title: "Database port"
                description: "Use a different port when the default is already taken."

                Components.AppTextField {
                    id: portField
                    width: 120
                    text: root.portDraft
                    inputMethodHints: Qt.ImhDigitsOnly
                    onTextChanged: root.portDraft = text
                }
            }

            Text {
                Layout.fillWidth: true
                text: Strings.t("current.runtime.port") + ": " + String(dashboardBridge.activeDatabasePort || "-")
                color: Theme.muted
                font.pixelSize: 12
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                text: Strings.t("reload")
                onClicked: loadPort()
            }
            Components.AppButton {
                id: saveButton
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                successText: "Saved"
                successDurationMs: 5000
                onClicked: {
                    var before = String(root.loadedPort)
                    var after = String(root.portDraft).trim()
                    var ok = dashboardBridge.updateDatabaseRuntimePort(after)
                    feedbackText = dashboardBridge.databaseRuntimeMessage
                    feedbackError = !ok
                    if (!ok) {
                        saveButton.successActive = false
                        return
                    }
                    saveButton.showSuccess()
                    var changed = before !== after
                    root.loadedPort = after
                    if (pageRoot.databaseRunning && changed) {
                        var appWindow = mainWindow()
                        if (appWindow && appWindow.openGlobalConfirm) {
                            appWindow.openGlobalConfirm(
                                Strings.t("restart.database.runtime"),
                                "Database runtime is running. Restart now to apply the new port?",
                                "database.restart_after_port_save",
                                {},
                                Strings.t("restart"),
                                Strings.t("later"),
                                runtimeWindow
                            )
                        }
                    }
                }
            }
        }
    }
}


