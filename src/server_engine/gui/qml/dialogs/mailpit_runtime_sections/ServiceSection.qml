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

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // Match the database Service tab: status, divider, then a details grid.

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle { width: 12; height: 12; radius: 6; color: String(dashboardBridge.mailpitServiceState || "").toLowerCase() === "running" ? Theme.success : Theme.danger }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Server Status"; color: Theme.muted; font.pixelSize: 11 }
                    Text { text: String(dashboardBridge.mailpitServiceState || "Stopped"); color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.65 }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 18
                rowSpacing: 8
                Text { text: "SMTP port"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.mailpitSmtpPort || "-"); color: Theme.muted; font.pixelSize: 13 }
                Text { text: "Web port"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.mailpitHttpPort || "-"); color: Theme.muted; font.pixelSize: 13 }
                Text { text: "Purpose"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: "Local email preview and SMTP capture"; color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
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
                text: Strings.t("reload")
                onClicked: pageRoot.refreshMailpitDraft()
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var ok = dashboardBridge.updateMailpitRuntimePorts(String(pageRoot.smtpPortDraft || "").trim(), String(pageRoot.webPortDraft || "").trim())
                    if (ok) {
                        pageRoot.refreshMailpitDraft()
                    }
                }
            }
        }
    }
}
