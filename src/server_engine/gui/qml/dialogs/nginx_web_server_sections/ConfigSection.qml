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
                text: Strings.t("configuration")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: "Edit the active Nginx main configuration file before startup."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: String(dashboardBridge.activeNginxConfigPath || "")
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: pageRoot.nginxConfigDraft
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                fontPixelSize: 12
                fontFamily: "Menlo"
                textColor: Theme.text
                readOnly: false
                onTextChanged: {
                    if (pageRoot) {
                        pageRoot.nginxConfigDraft = text
                    }
                }
            }
        }

        footerLeft: Text {
            text: pageRoot.nginxConfigFeedback
            color: dashboardBridge.nginxRuntimeError ? "#bb4d4d" : "#4aa94b"
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
                text: Strings.t("open.path")
                onClicked: dashboardBridge.revealInFinder(String(dashboardBridge.activeNginxConfigPath || ""))
            }
            Components.AppButton {
                text: Strings.t("restore.original")
                onClicked: {
                    var ok = dashboardBridge.restoreActiveNginxConfigOriginal()
                    pageRoot.nginxConfigFeedback = dashboardBridge.nginxRuntimeMessage
                    if (ok) {
                        if (runtimeWindow && runtimeWindow.refreshNginxDrafts) {
                            runtimeWindow.refreshNginxDrafts()
                        }
                    }
                }
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var ok = dashboardBridge.saveActiveNginxConfigContent(pageRoot.nginxConfigDraft)
                    pageRoot.nginxConfigFeedback = dashboardBridge.nginxRuntimeMessage
                    if (ok) {
                        if (runtimeWindow && runtimeWindow.refreshNginxDrafts) {
                            runtimeWindow.refreshNginxDrafts()
                        }
                    }
                }
            }
        }
    }
}
