import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: nginxWebServerWindow

    required property var root
    readonly property var dashboardBridge: root.dashboardBridge
    property string nginxPopupSection: "service"
    property var nginxPopupSections: [
        { id: "service", label: Strings.t("service") },
        { id: "settings", label: Strings.t("settings") },
        { id: "switch.version", label: Strings.t("switch.version") },
        { id: "configuration", label: Strings.t("configuration") },
        { id: "port", label: Strings.t("port") },
        { id: "logs", label: Strings.t("logs") }
    ]
    readonly property bool webRunning: {
        var items = dashboardBridge.homeServiceItems || []
        for (var i = 0; i < items.length; i++) {
            if (String(items[i].id || "") === "web") {
                return String(items[i].status || "").toLowerCase() === "running"
            }
        }
        return false
    }
    readonly property bool webBusy: !!dashboardBridge.stackActionBusy

    width: 760
    height: 620
    minimumWidth: width
    maximumWidth: width
    minimumHeight: 400
    maximumHeight: 820
    visible: root.nginxWebServerPopupOpen
    title: dashboardBridge.currentWebServerLabel
    modality: Qt.ApplicationModal
    transientParent: root.Window.window
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    color: Theme.surface

    Behavior on height {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    function applyRuntimeWindowHeight(sectionId) {
        var nextHeight = 620
        switch (String(sectionId || "")) {
        case "service":
            nextHeight = 400
            break
        case "settings":
            nextHeight = 620
            break
        case "switch.version":
            nextHeight = 520
            break
        case "configuration":
            nextHeight = 560
            break
        case "port":
            nextHeight = 500
            break
        case "logs":
            nextHeight = 640
            break
        default:
            nextHeight = 620
            break
        }
        nextHeight = Math.max(minimumHeight, Math.min(maximumHeight, nextHeight))
        if (height !== nextHeight) {
            height = nextHeight
        }
    }

    function refreshNginxDrafts() {
        root.nginxRuntimeModel = dashboardBridge.webServerRuntimeItems("nginx")
        root.nginxConfigDraft = String(dashboardBridge.activeNginxConfigContent || "")
        root.nginxConfigFeedback = ""
        root.nginxPortDraft = String(dashboardBridge.settingsWebPort || "8080")
        root.nginxPortLoaded = root.nginxPortDraft
        root.nginxWorkerProcessesDraft = dashboardBridge.settingsNginxWorkerProcesses
        root.nginxWorkerConnectionsDraft = dashboardBridge.settingsNginxWorkerConnections
        root.nginxKeepaliveTimeoutDraft = dashboardBridge.settingsNginxKeepaliveTimeout
        root.nginxClientMaxBodySizeDraft = dashboardBridge.settingsNginxClientMaxBodySize
        root.nginxSendfileDraft = dashboardBridge.settingsNginxSendfile
        root.nginxGzipDraft = dashboardBridge.settingsNginxGzip
        root.nginxServerTokensDraft = dashboardBridge.settingsNginxServerTokens
        root.nginxErrorLogPathDraft = dashboardBridge.settingsNginxErrorLogPath
        root.nginxGlobalDirectivesDraft = dashboardBridge.settingsNginxGlobalDirectives
    }

    function nginxSectionSource(sectionLabel) {
        switch (sectionLabel) {
        case "service":
            return "nginx_web_server_sections/ServiceSection.qml"
        case "settings":
            return "nginx_web_server_sections/NginxSettingsPage.qml"
        case "switch.version":
            return "nginx_web_server_sections/SwitchVersionSection.qml"
        case "configuration":
            return "nginx_web_server_sections/ConfigFileSection.qml"
        case "port":
            return "nginx_web_server_sections/PortSection.qml"
        case "logs":
            return "nginx_web_server_sections/LogsSection.qml"
        default:
            return "nginx_web_server_sections/PlaceholderSection.qml"
        }
    }

    function nginxSectionIcon(sectionLabel) {
        switch (sectionLabel) {
        case "service":
            return "power-accent"
        case "settings":
            return "settings"
        case "switch.version":
            return "git-compare-arrows"
        case "configuration":
            return "file-text"
        case "port":
            return "ethernet-port"
        case "logs":
            return "file-text"
        default:
            return "settings"
        }
    }

    function nginxSectionLabel(sectionLabel) {
        for (var i = 0; i < nginxPopupSections.length; i++) {
            if (nginxPopupSections[i].id === sectionLabel) {
                return nginxPopupSections[i].label
            }
        }
        return String(sectionLabel || "")
    }

    onVisibleChanged: {
        if (visible) {
            refreshNginxDrafts()
            nginxPopupSection = "settings"
            dashboardBridge.clearAppSettingsFeedback()
            Qt.callLater(function() {
                applyRuntimeWindowHeight(nginxPopupSection)
            })
        } else {
            root.nginxWebServerPopupOpen = false
        }
    }

    Components.PageWindowFrame {
        moveWindow: nginxWebServerWindow
        bodyMargins: 16

        headerContent: Item {
            anchors.fill: parent

            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                text: nginxSectionLabel(nginxPopupSection)
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Item {
                anchors.fill: parent
                anchors.topMargin: 28
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.bottomMargin: 6
                clip: true

                Row {
                    height: 58
                    spacing: 6

                    Repeater {
                        model: nginxPopupSections

                        delegate: Components.TopIconTab {
                            id: nginxTopTabItem
                            required property int index
                            property var navItem: nginxPopupSections[index]
                            selected: nginxPopupSection === navItem.id
                            label: nginxTopTabItem.navItem.label
                            iconSource: "../icons/lucide/" + nginxSectionIcon(nginxTopTabItem.navItem.id) + ".svg"
                            onClicked: {
                                nginxPopupSection = nginxTopTabItem.navItem.id
                                nginxWebServerWindow.applyRuntimeWindowHeight(nginxTopTabItem.navItem.id)
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 20

            Loader {
                id: nginxSectionLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                source: nginxSectionSource(nginxPopupSection)
                onLoaded: {
                    if (item) {
                        item.pageRoot = root
                        item.dashboardBridge = dashboardBridge
                        item.runtimeWindow = nginxWebServerWindow
                    }
                    Qt.callLater(function() {
                        nginxWebServerWindow.applyRuntimeWindowHeight(nginxPopupSection)
                    })
                }
            }
        }
    }
}
