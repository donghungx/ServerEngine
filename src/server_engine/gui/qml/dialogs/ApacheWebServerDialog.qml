import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: apacheWebServerWindow

    required property var root
    readonly property var dashboardBridge: root.dashboardBridge
    property string apachePopupSection: "general"
    property var apachePopupSections: [
        { id: "general", label: Strings.t("general") },
        { id: "service", label: Strings.t("service") },
        { id: "switch.version", label: Strings.t("switch.version") },
        { id: "modules", label: Strings.t("apache.modules") },
        { id: "configuration", label: Strings.t("configuration") },
        { id: "port", label: Strings.t("port") },
        { id: "logs", label: Strings.t("logs") }
    ]
    property string apacheGeneralLogLevelDraft: "warn"
    property string apacheGeneralDefineFlagsDraft: ""
    property bool apacheGeneralSyntaxCheckDraft: false
    property bool apacheGeneralDebugModeDraft: false
    property bool apacheGeneralSkipDocumentRootCheckDraft: false
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
    visible: root.apacheWebServerPopupOpen
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
        case "switch.version":
            nextHeight = 520
            break
        case "modules":
            nextHeight = 620
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
        case "general":
        default:
            nextHeight = 620
            break
        }
        nextHeight = Math.max(minimumHeight, Math.min(maximumHeight, nextHeight))
        if (height !== nextHeight) {
            height = nextHeight
        }
    }

    function refreshApacheDrafts() {
        root.apacheRuntimeModel = dashboardBridge.webServerRuntimeItems("apache")
        root.apacheModulesDraft = dashboardBridge.apacheModuleItems
        root.apacheConfigDraft = String(dashboardBridge.activeApacheConfigContent || "")
        root.apacheConfigFeedback = ""
        root.apachePortDraft = String(dashboardBridge.settingsWebPort || "8080")
        root.apachePortLoaded = root.apachePortDraft
        root.apacheErrorLogPathDraft = dashboardBridge.settingsApacheErrorLogPath
        apacheWebServerWindow.apacheGeneralLogLevelDraft = "warn"
        apacheWebServerWindow.apacheGeneralDefineFlagsDraft = ""
        apacheWebServerWindow.apacheGeneralSyntaxCheckDraft = false
        apacheWebServerWindow.apacheGeneralDebugModeDraft = false
        apacheWebServerWindow.apacheGeneralSkipDocumentRootCheckDraft = false
    }

    function apacheSectionSource(sectionLabel) {
        switch (sectionLabel) {
        case "general":
            return "apache_web_server_sections/GeneralSection.qml"
        case "service":
            return "apache_web_server_sections/ServiceSection.qml"
        case "switch.version":
            return "apache_web_server_sections/SwitchVersionSection.qml"
        case "modules":
            return "apache_web_server_sections/ModulesSection.qml"
        case "configuration":
            return "apache_web_server_sections/ConfigFileSection.qml"
        case "port":
            return "apache_web_server_sections/PortSection.qml"
        case "logs":
            return "apache_web_server_sections/LogsSection.qml"
        default:
            return "apache_web_server_sections/PlaceholderSection.qml"
        }
    }

    function apacheSectionIcon(sectionLabel) {
        switch (sectionLabel) {
        case "general":
            return "settings"
        case "service":
            return "power-accent"
        case "switch.version":
            return "git-compare-arrows"
        case "modules":
            return "component"
        case "configuration":
            return "file-sliders"
        case "port":
            return "ethernet-port"
        case "logs":
            return "file-text"
        default:
            return "settings"
        }
    }

    function apacheSectionLabel(sectionLabel) {
        for (var i = 0; i < apachePopupSections.length; i++) {
            if (apachePopupSections[i].id === sectionLabel) {
                return apachePopupSections[i].label
            }
        }
        return String(sectionLabel || "")
    }

    onVisibleChanged: {
        if (visible) {
            refreshApacheDrafts()
            apachePopupSection = "general"
            dashboardBridge.clearAppSettingsFeedback()
            Qt.callLater(function() {
                applyRuntimeWindowHeight(apachePopupSection)
            })
        } else {
            root.apacheWebServerPopupOpen = false
        }
    }

    Components.PageWindowFrame {
        moveWindow: apacheWebServerWindow
        bodyMargins: 16

        headerContent: Item {
            anchors.fill: parent

            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                text: apacheSectionLabel(apachePopupSection)
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
                        model: apachePopupSections

                        delegate: Components.TopIconTab {
                            id: apacheTopTabItem
                            required property int index
                            property var navItem: apachePopupSections[index]
                            selected: apachePopupSection === navItem.id
                            label: apacheTopTabItem.navItem.label
                            iconSource: "../icons/lucide/" + apacheSectionIcon(apacheTopTabItem.navItem.id) + ".svg"
                            onClicked: {
                                apachePopupSection = apacheTopTabItem.navItem.id
                                apacheWebServerWindow.applyRuntimeWindowHeight(apacheTopTabItem.navItem.id)
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
                id: apacheSectionLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                source: apacheSectionSource(apachePopupSection)
                onLoaded: {
                    if (item) {
                        item.pageRoot = root
                        item.dashboardBridge = dashboardBridge
                        item.runtimeWindow = apacheWebServerWindow
                    }
                    Qt.callLater(function() {
                        apacheWebServerWindow.applyRuntimeWindowHeight(apachePopupSection)
                    })
                }
            }
        }
    }
}
