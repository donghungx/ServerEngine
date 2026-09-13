import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root
    property var siteData: ({})
    property var dashboardBridge
    property string configText: ""
    property string configPath: ""
    property string feedbackText: ""
    property bool feedbackError: false
    property string loadedConfigSiteId: ""
    property string currentSiteId: ""

    function loadConfig() {
        if (!dashboardBridge || !siteData || !siteData.id) {
            return
        }
        if (loadedConfigSiteId === String(siteData.id)) {
            return
        }
        configPath = dashboardBridge.siteActiveConfigPath(String(siteData.id))
        configText = dashboardBridge.siteActiveConfigContent(String(siteData.id))
        configEditor.text = configText
        loadedConfigSiteId = String(siteData.id)
        feedbackText = ""
        feedbackError = false
    }

    Component.onCompleted: {
        currentSiteId = siteData && siteData.id ? String(siteData.id) : ""
        loadConfig()
    }
    onSiteDataChanged: {
        var nextId = siteData && siteData.id ? String(siteData.id) : ""
        if (nextId !== currentSiteId) {
            currentSiteId = nextId
            loadedConfigSiteId = ""
            configPath = ""
            configText = ""
            configEditor.text = ""
            loadConfig()
        }
    }
    onDashboardBridgeChanged: {
        loadedConfigSiteId = ""
        loadConfig()
    }

    Components.SettingsTabFrame {
        anchors.fill: parent

        ColumnLayout {
            spacing: 16

            Label {
                Layout.fillWidth: true
                text: (dashboardBridge && dashboardBridge.settingsWebServer === "nginx"
                    ? "Active Nginx site configuration file"
                    : "Active Apache site configuration file")
                color: Theme.muted
                font.pixelSize: 13
            }

            Label {
                Layout.fillWidth: true
                text: configPath
                color: Theme.text
                font.pixelSize: 12
                elide: Text.ElideMiddle
                visible: configPath.length > 0
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Components.AppScrollEditor {
                    anchors.fill: parent
                    id: configEditor
                    text: ""
                    readOnly: false
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    textFormat: TextEdit.PlainText
                    fontFamily: "Menlo"
                    fontPixelSize: 12
                    textColor: Theme.text
                    contentPadding: 8
                }
            }

        }

        footerLeft: Text {
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackError ? Theme.danger : Theme.success
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        footerRight: RowLayout {
            spacing: 12

            Components.AppButton {
                text: Strings.t("test")
                onClicked: {
                    if (!dashboardBridge || !siteData || !siteData.id) {
                        return
                    }
                    var ok = dashboardBridge.testSiteActiveConfigDraft(String(siteData.id), configEditor.text)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackError = !ok
                }
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    if (!dashboardBridge || !siteData || !siteData.id) {
                        return
                    }
                    var ok = dashboardBridge.saveSiteActiveConfig(String(siteData.id), configEditor.text)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackError = !ok
                }
            }

            Components.AppButton {
                text: Strings.t("reload")
                onClicked: {
                    loadedConfigSiteId = ""
                    loadConfig()
                }
            }
        }
    }
}
