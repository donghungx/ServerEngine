import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    Connections {
        target: mainWindow()
        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "database.restore_original_config") {
                var ok = dashboardBridge.restoreActiveDatabaseConfigOriginal()
                pageRoot.databaseConfigFeedback = dashboardBridge.databaseRuntimeMessage
                if (ok) {
                    pageRoot.refreshDatabaseConfigDraft()
                }
            } else if (actionId === "database.restart_after_config_save") {
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

            Text {
                Layout.fillWidth: true
                text: dashboardBridge.activeDatabaseConfigPath
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: pageRoot.databaseConfigDraft
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                fontPixelSize: 12
                fontFamily: "Menlo"
                textColor: Theme.text
                readOnly: false
                onTextChanged: {
                    if (pageRoot) {
                        pageRoot.databaseConfigDraft = text
                    }
                }
            }
        }

        footerRight: Row {
            spacing: 8

            Components.QuickActionButton {
                tooltip: Strings.t("reload")
                iconSource: "../icons/lucide/rotate-cw.svg"
                onClicked: pageRoot.refreshDatabaseConfigDraft()
            }

            Components.QuickActionButton {
                tooltip: Strings.t("open.path")
                iconSource: "../icons/lucide/file-sliders.svg"
                onClicked: dashboardBridge.revealInFinder(dashboardBridge.activeDatabaseConfigPath)
            }

            Components.AppButton {
                id: restoreButton
                text: Strings.t("restore.original")
                onClicked: {
                    var appWindow = mainWindow()
                    if (appWindow && appWindow.openGlobalConfirm) {
                        appWindow.openGlobalConfirm(
                            Strings.t("restore.original"),
                            "Restore the original config file for this runtime? Unsaved editor changes will be discarded.",
                            "database.restore_original_config",
                            {},
                            Strings.t("restore.original"),
                            Strings.t("cancel"),
                            runtimeWindow
                        )
                        return
                    }
                    var ok = dashboardBridge.restoreActiveDatabaseConfigOriginal()
                    pageRoot.databaseConfigFeedback = dashboardBridge.databaseRuntimeMessage
                    if (ok) {
                        pageRoot.refreshDatabaseConfigDraft()
                    }
                }
            }

            Components.AppButton {
                id: saveButton
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                successText: "Saved"
                successDurationMs: 5000
                onClicked: {
                    var ok = dashboardBridge.saveActiveDatabaseConfigContent(pageRoot.databaseConfigDraft)
                    pageRoot.databaseConfigFeedback = dashboardBridge.databaseRuntimeMessage
                    if (ok) {
                        saveButton.showSuccess()
                        pageRoot.refreshDatabaseConfigDraft()
                        if (pageRoot && pageRoot.databaseRunning) {
                            var appWindow = mainWindow()
                            if (appWindow && appWindow.openGlobalConfirm) {
                                appWindow.openGlobalConfirm(
                                    Strings.t("restart.database.runtime"),
                                    "Database runtime is running. Restart now to apply the new config file?",
                                    "database.restart_after_config_save",
                                    {},
                                    Strings.t("restart"),
                                    Strings.t("later"),
                                    runtimeWindow
                                )
                            }
                        }
                    } else {
                        saveButton.successActive = false
                    }
                }
            }
        }
    }
}


