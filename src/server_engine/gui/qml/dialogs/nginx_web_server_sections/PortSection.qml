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
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("port")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: "Use this when port 80 is already taken, or when you want Nginx isolated from another local install."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: 10

                Text {
                    text: Strings.t("port")
                    color: Theme.muted
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Components.AppTextField {
                    width: 120
                    text: pageRoot.nginxPortDraft
                    onTextChanged: pageRoot.nginxPortDraft = text
                    placeholderText: "8080"
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: pageRoot.nginxConfigFeedback
            color: dashboardBridge.stackFeedbackError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                text: Strings.t("reload")
                onClicked: {
                    if (runtimeWindow && runtimeWindow.refreshNginxDrafts) {
                        runtimeWindow.refreshNginxDrafts()
                    }
                }
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var candidatePort = String(pageRoot.nginxPortDraft || "").trim()
                    var ok = dashboardBridge.updateNginxRuntimePort(candidatePort)
                    pageRoot.nginxConfigFeedback = dashboardBridge.nginxRuntimeMessage || dashboardBridge.stackFeedbackMessage
                    if (ok) {
                        pageRoot.nginxPortLoaded = candidatePort
                        if (runtimeWindow && runtimeWindow.refreshNginxDrafts) {
                            runtimeWindow.refreshNginxDrafts()
                        }
                    }
                }
            }
        }
    }
}
