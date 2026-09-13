import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    anchors.fill: parent

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    function savePortsNow() {
        var ok = dashboardBridge.updateMailpitRuntimePorts(String(pageRoot.smtpPortDraft || "").trim(), String(pageRoot.webPortDraft || "").trim())
        if (ok) {
            saveButton.showSuccess()
            if (pageRoot && pageRoot.mailpitRunning) {
                var appWindow = mainWindow()
                if (appWindow && appWindow.openGlobalConfirm) {
                    appWindow.openGlobalConfirm(
                        "Restart Required",
                        "Mailpit needs to restart to apply the new port settings. Do you want to restart now?",
                        "mailpit.restart_after_port_save",
                        {},
                        "Restart",
                        "Cancel",
                        runtimeWindow
                    )
                } else if (dashboardBridge && dashboardBridge.restartMailpitRuntime) {
                    dashboardBridge.restartMailpitRuntime()
                }
            }
        } else {
            saveButton.successActive = false
        }
        return ok
    }

    Connections {
        target: mainWindow()
        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "mailpit.restart_after_port_save") {
                if (dashboardBridge && dashboardBridge.restartMailpitRuntime) {
                    dashboardBridge.restartMailpitRuntime()
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
            spacing: 16

            Components.SettingsLabeledInput {
                title: Strings.t("smtp.port")
                description: "Set the SMTP port Mailpit listens on."

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Components.AppTextField {
                        id: smtpPortField
                        Layout.fillWidth: true
                        text: pageRoot.smtpPortDraft
                        onTextChanged: pageRoot.smtpPortDraft = text
                        placeholderText: "1025"
                    }
                }
            }

            Components.SettingsLabeledInput {
                title: Strings.t("web.port")
                description: "Set the web UI port Mailpit listens on."

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Components.AppTextField {
                        id: webPortField
                        Layout.fillWidth: true
                        text: pageRoot.webPortDraft
                        onTextChanged: pageRoot.webPortDraft = text
                        placeholderText: "8025"
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: dashboardBridge.mailpitRuntimeMessage
            color: dashboardBridge.mailpitRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            width: parent.width
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                id: saveButton
                successText: "Saved"
                successDurationMs: 5000
                onClicked: savePortsNow()
            }
        }
    }
}
