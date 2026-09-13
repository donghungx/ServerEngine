import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
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

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    Connections {
        target: mainWindow()

        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "postgresql.restart_after_config_save") {
                bridge().restartPostgresqlRuntime && bridge().restartPostgresqlRuntime()
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

            Label {
                Layout.fillWidth: true
                text: Strings.t("configuration")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("the.app.generates.a.dedicated.config.file.for.the.active.runtime.version.before.startup")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: String(bridge().activePostgresqlConfigPath || "")
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: pageRoot.postgresqlConfigDraft
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                fontPixelSize: 12
                fontFamily: "Menlo"
                textColor: Theme.text
                readOnly: false
                onTextChanged: {
                    if (pageRoot) {
                        pageRoot.postgresqlConfigDraft = text
                    }
                }
            }
        }

        footerLeft: Text {
            text: pageRoot.postgresqlConfigFeedback
            color: "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("reload")
                onClicked: pageRoot.refreshPostgresqlConfigDraft()
            }

            Components.AppButton {
                text: Strings.t("open.path")
                onClicked: bridge().revealInFinder && bridge().revealInFinder(String(bridge().activePostgresqlConfigPath || ""))
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var ok = bridge().saveActivePostgresqlConfigContent ? bridge().saveActivePostgresqlConfigContent(pageRoot.postgresqlConfigDraft) : false
                    pageRoot.postgresqlConfigFeedback = String(bridge().postgresqlRuntimeMessage || "")
                    if (ok) {
                        pageRoot.refreshPostgresqlConfigDraft()
                        if (pageRoot && pageRoot.postgresqlRunning) {
                            var appWindow = mainWindow()
                            if (appWindow && appWindow.openGlobalConfirm) {
                                appWindow.openGlobalConfirm(
                                "Restart PostgreSQL runtime",
                                "PostgreSQL runtime is running. Restart now to apply the updated configuration file?",
                                "postgresql.restart_after_config_save",
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

            Components.AppButton {
                text: Strings.t("restore.original")
                onClicked: {
                    var ok = bridge().restoreActivePostgresqlConfigOriginal ? bridge().restoreActivePostgresqlConfigOriginal() : false
                    pageRoot.postgresqlConfigFeedback = String(bridge().postgresqlRuntimeMessage || "")
                    if (ok) {
                        pageRoot.refreshPostgresqlConfigDraft()
                    }
                }
            }
        }
    }
}


