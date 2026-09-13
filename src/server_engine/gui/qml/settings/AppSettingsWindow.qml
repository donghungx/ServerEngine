import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components" as Components
import "../dialogs" as Dialogs
import "../theme"
import "../i18n"

Window {
    id: appSettingsWindow
    required property var window
    required property var bridge
    visible: window.appSettingsOpen
    width: 736
    height: 540
    minimumWidth: width
    maximumWidth: width
    minimumHeight: 376
    maximumHeight: 960
    title: Strings.t("app.settings.title")
    color: Theme.surface
    property bool runtimeInstallFeedbackActive: !!bridge.runtimeInstallBusy
        || String(bridge.runtimeInstallStatus || "").trim().length > 0
    property bool runtimeInstallOpen: false
    property var runtimeInstallSelectedItem: ({})
    property string appSettingsFeedbackSection: ""
    property bool appSettingsFeedbackVisible: false
    property string scopedAppSettingsMessage: appSettingsFeedbackVisible
        && appSettingsFeedbackSection === window.appSettingsSection
        && !(window.appSettingsSection !== "Runtime" && runtimeInstallFeedbackActive)
        ? bridge.appSettingsMessage
        : ""
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowCloseButtonHint

    Behavior on height {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    onVisibleChanged: {
        if (visible) {
            var targetSection = window.appSettingsInitialSection.length > 0
                ? window.appSettingsInitialSection
                : "General"
            var targetRuntimeService = window.appSettingsInitialRuntimeService.length > 0
                ? window.appSettingsInitialRuntimeService
                : "php"
            window.appSettingsSection = targetSection
            Qt.callLater(function() {
                applySectionWindowHeight(window.appSettingsSection)
            })
            bridge.clearAppSettingsFeedback()
            appSettingsWindow.appearanceSettingsReady = false
            appearanceThemeCombo.currentIndex = appSettingsWindow.findAppearanceThemeIndex(bridge.settingsAppearanceTheme)
            appearanceLanguageCombo.currentIndex = appSettingsWindow.findAppearanceLanguageIndex(bridge.settingsAppearanceLanguage)
            appSettingsWindow.appearanceAccentDraft = bridge.settingsAppearanceAccentColor
            autoStartStackCheck.checked = bridge.settingsAutoStartStack
            environmentRootField.text = bridge.settingsEnvironmentRoot
            appSettingsWindow.optionsUpdateModeDraft = "Automatically download and install"
            appSettingsWindow.optionsStartWithSystemDraft = bridge.settingsAutoStartStack
            appSettingsWindow.optionsShowInMenuBarDraft = bridge.systemTrayVisible
            appSettingsWindow.optionsPromptBeforeQuitDraft = true
            appSettingsWindow.optionsStopServersOnQuitDraft = true
            appSettingsWindow.optionsNotificationModeDraft = "Important only"
            appSettingsWindow.optionsSendAnonymousUsageDataDraft = false
            appSettingsWindow.optionsLogModeDraft = "Never delete logs"
            phpMyAdminVersionCombo.currentIndex = appSettingsWindow.safeComboIndex(phpMyAdminVersionCombo, bridge.activePhpMyAdminVersion)
            phpMyAdminPhpVersionCombo.currentIndex = appSettingsWindow.safeComboIndex(phpMyAdminPhpVersionCombo, bridge.phpMyAdminPhpVersion)
            phpDefaultVersionCombo.currentIndex = appSettingsWindow.safeComboIndex(phpDefaultVersionCombo, bridge.settingsDefaultPhpVersion)
            nodeDefaultVersionCombo.currentIndex = appSettingsWindow.safeComboIndex(nodeDefaultVersionCombo, bridge.settingsNodeVersion)
            phpLogToFileCheck.checked = bridge.settingsPhpLogToFile
            phpLogToScreenCheck.checked = bridge.settingsPhpLogToScreen
            phpLogPathField.text = bridge.settingsPhpLogPath
            databaseEngineCombo.currentIndex = appSettingsWindow.safeComboIndex(databaseEngineCombo, bridge.settingsDatabaseEngine)
            runtimeModel = bridge.databaseRuntimesByEngine(bridge.settingsDatabaseEngine)
            runtimeCombo.currentIndex = findRuntimeIndex(bridge.settingsDatabaseRuntime)
            cacheRuntimeModel = bridge.redisRuntimeItems
            redisAppSettingsRuntimeCombo.currentIndex = findCacheRuntimeIndex(cacheRuntimeModel, bridge.settingsRedisRuntime)
            webServerCombo.currentIndex = appSettingsWindow.safeComboIndex(webServerCombo, bridge.settingsWebServer)
            webPortField.text = bridge.settingsWebPort
            databasePortField.text = bridge.settingsDatabasePort
            redisPortField.text = bridge.settingsRedisPort
            memcachedPortField.text = bridge.activeMemcachedPort
            mailpitSmtpPortField.text = bridge.settingsMailpitSmtpPort
            mailpitHttpPortField.text = bridge.settingsMailpitHttpPort
            defaultProjectFolderField.text = bridge.settingsDefaultProjectFolder
            runtimeManagerService = targetRuntimeService
            refreshRuntimeManager()
            Strings.language = String(bridge.settingsAppearanceLanguage || "en").toLowerCase()
            appSettingsWindow.appearanceSettingsReady = true
            window.appSettingsInitialSection = ""
            window.appSettingsInitialRuntimeService = ""
        } else {
            window.refreshThemeState()
            appSettingsWindow.runtimeInstallOpen = false
            appSettingsWindow.runtimeInstallSelectedItem = ({})
            window.appSettingsOpen = false
        }
    }

    property var runtimeModel: []
    property var cacheRuntimeModel: []
    property var memcachedRuntimeModel: bridge.memcachedRuntimeItems
    property string runtimeManagerService: "php"
    property var runtimeManagerServices: [
        { label: Strings.t("php"), service: "php" },
        { label: Strings.t("node"), service: "node" },
        { label: Strings.t("phpmyadmin"), service: "phpmyadmin" },
        { label: Strings.t("apache"), service: "apache" },
        { label: Strings.t("nginx"), service: "nginx" },
        { label: Strings.t("mysql"), service: "mysql" },
        { label: Strings.t("mariadb"), service: "mariadb" },
        { label: Strings.t("mongodb"), service: "mongodb" },
        { label: Strings.t("postgresql"), service: "postgresql" },
        { label: Strings.t("redis"), service: "redis" },
        { label: Strings.t("memcached"), service: "memcached" },
        { label: Strings.t("mailpit"), service: "mailpit" }
    ]
    property var runtimeManagerModel: []
    property var runtimeServerModel: []
    property string appearanceAccentDraft: "#007bff"
    property bool appearanceSettingsReady: false
    property string optionsUpdateModeDraft: "Automatically download and install"
    property bool optionsStartWithSystemDraft: true
    property bool optionsShowInMenuBarDraft: true
    property bool optionsPromptBeforeQuitDraft: true
    property bool optionsStopServersOnQuitDraft: true
    property string optionsNotificationModeDraft: "Important only"
    property bool optionsSendAnonymousUsageDataDraft: false
    property string optionsLogModeDraft: "Never delete logs"
    property bool webServerRestartAfterChangesDraft: false
    property bool webServerEnableCompressionDraft: false
    property string webServerKeepAliveTimeoutDraft: "75s"
    property bool databaseRestartAfterChangesDraft: false
    property bool databaseAllowNetworkAccessDraft: false
    property bool databaseUseRandomFreePortIfBusyDraft: false
    property bool databaseSnapshotBeforeImportDraft: false
    property bool nodeAutoInstallDependenciesDraft: false
    property bool nodeAllowNetworkAccessDraft: false
    property alias appearanceThemeCombo: appearanceSettingsPage.appearanceThemeCombo
    property alias appearanceLanguageCombo: appearanceSettingsPage.appearanceLanguageCombo
    property alias autoStartStackCheck: generalSettingsPage.autoStartStackCheck
    property alias defaultProjectFolderField: generalSettingsPage.defaultProjectFolderField
    property alias environmentRootField: generalSettingsPage.environmentRootField
    property alias phpMyAdminVersionCombo: phpMyAdminSettingsPage.phpMyAdminVersionCombo
    property alias phpMyAdminPhpVersionCombo: phpMyAdminSettingsPage.phpMyAdminPhpVersionCombo
    property alias phpDefaultVersionCombo: phpSettingsPage.phpDefaultVersionCombo
    property alias phpLogToFileCheck: phpSettingsPage.phpLogToFileCheck
    property alias phpLogToScreenCheck: phpSettingsPage.phpLogToScreenCheck
    property alias phpLogPathField: phpSettingsPage.phpLogPathField
    property alias nodeDefaultVersionCombo: nodeSettingsPage.nodeDefaultVersionCombo
    property alias databaseEngineCombo: databaseSettingsPage.databaseEngineCombo
    property alias runtimeCombo: databaseSettingsPage.runtimeCombo
    property alias webServerCombo: webServerSettingsPage.webServerCombo
    property alias redisAppSettingsRuntimeCombo: redisSettingsPage.redisAppSettingsRuntimeCombo
    property alias webPortField: portsSettingsPage.webPortField
    property alias databasePortField: portsSettingsPage.databasePortField
    property alias redisPortField: portsSettingsPage.redisPortField
    property alias memcachedPortField: portsSettingsPage.memcachedPortField
    property alias mailpitSmtpPortField: portsSettingsPage.mailpitSmtpPortField
    property alias mailpitHttpPortField: portsSettingsPage.mailpitHttpPortField

    function findRuntimeIndex(runtimeId) {
        for (var i = 0; i < runtimeModel.length; i++) {
            if (runtimeModel[i].id === runtimeId) {
                return i
            }
        }
        return runtimeModel.length > 0 ? 0 : -1
    }

    function findRuntimeIndexInModel(model, runtimeId) {
        for (var i = 0; i < model.length; i++) {
            if (model[i].id === runtimeId || model[i].version === runtimeId) {
                return i
            }
        }
        return model.length > 0 ? 0 : -1
    }

    function safeComboIndex(combo, value) {
        var found = combo.find(value)
        return found >= 0 ? found : 0
    }

    function normalizeSectionId(sectionLabel) {
        var raw = String(sectionLabel || "").toLowerCase()
        if (raw === "web server") {
            return "web"
        }
        return raw
    }

    function sectionDisplayLabel(sectionLabel) {
        var sectionId = normalizeSectionId(sectionLabel)
        for (var i = 0; i < window.appSettingsSections.length; i++) {
            if (window.appSettingsSections[i].id === sectionId) {
                return window.appSettingsSections[i].label
            }
        }
        return String(sectionLabel || "")
    }

    function sectionIndex(sectionLabel) {
        var pageOrder = [
            "appearance",
            "general",
            "phpmyadmin",
            "php",
            "node",
            "runtime",
            "database",
            "web",
            "redis",
            "ports"
        ]
        var normalized = normalizeSectionId(sectionLabel)
        for (var i = 0; i < pageOrder.length; i++) {
            if (pageOrder[i] === normalized) {
                return i
            }
        }
        return 1
    }

    function applySectionWindowHeight(sectionLabel) {
        var nextHeight = sectionDefaultHeight(sectionLabel)
        var requestedHeight = nextHeight
        nextHeight = Math.max(minimumHeight, Math.min(maximumHeight, nextHeight))

        if (height !== nextHeight) {
            height = nextHeight
        }
    }

    function refreshSectionWindowHeight() {
        Qt.callLater(function() {
            appSettingsWindow.applySectionWindowHeight(window.appSettingsSection)
        })
    }

    function sectionDefaultHeight(sectionLabel) {
        var normalized = normalizeSectionId(sectionLabel)
        let nextHeight
        switch (normalized) {
        case "general":
            nextHeight = 720
            break
        case "appearance":
            nextHeight = 200
            break
        case "phpmyadmin":
            nextHeight = 280
            break
        case "php":
            nextHeight = 380
            break
        case "node":
            nextHeight = 404
            break
        case "runtime":
            nextHeight = 640
            break
        case "database":
            nextHeight = 516
            break
        case "web":
            nextHeight = 440
            break
        case "redis":
            nextHeight = 480
            break
        case "ports":
            nextHeight = 616
            break
        default:
            nextHeight = 680
            break
        }
        return nextHeight
    }

    function findAppearanceThemeIndex(value) {
        var mode = String(value || "system").toLowerCase()
        var items = appearanceThemeCombo.model
        for (var i = 0; i < items.length; i++) {
            if (String(items[i].value || "").toLowerCase() === mode) {
                return i
            }
        }
        return 0
    }

    function findAppearanceLanguageIndex(value) {
        var lang = String(value || "en").toLowerCase()
        if (lang === "zh_cn" || lang === "zh-sg") {
            lang = "zh-hans"
        } else if (lang === "zh_tw" || lang === "zh_hk" || lang === "zh-mo") {
            lang = "zh-hant"
        }
        var items = appearanceLanguageCombo.model
        for (var i = 0; i < items.length; i++) {
            if (String(items[i].value || "").toLowerCase() === lang) {
                return i
            }
        }
        return 0
    }

    function normalizeAccentColor(value) {
        return String(value || "#007bff").toLowerCase()
    }

    function findCacheRuntimeIndex(model, runtimeId) {
        for (var i = 0; i < model.length; i++) {
            if (model[i].id === runtimeId) {
                return i
            }
        }
        return model.length > 0 ? 0 : -1
    }

    function settingsIconSource(iconName, selected) {
        return "../icons/lucide/" + iconName + ".svg"
    }

    function runtimeManagerServiceIndex(service) {
        for (var i = 0; i < runtimeManagerServices.length; i++) {
            if (runtimeManagerServices[i].service === service) {
                return i
            }
        }
        return 0
    }

    function refreshRuntimeManager() {
        runtimeManagerModel = bridge.runtimeManagerItems(runtimeManagerService)
    }

    function refreshRuntimeServerModel() {
        runtimeServerModel = []
        bridge.requestRuntimeServerItems(runtimeManagerService)
    }

    Connections {
        target: appSettingsWindow.bridge ? appSettingsWindow.bridge : null
        function onAppSettingsFeedbackChanged() {
            var nextMessage = String(bridge.appSettingsMessage || "").trim()
            if (nextMessage.length > 0) {
                appSettingsWindow.appSettingsFeedbackSection = window.appSettingsSection
                appSettingsWindow.appSettingsFeedbackVisible = true
                appSettingsFeedbackHideTimer.restart()
            } else {
                appSettingsWindow.appSettingsFeedbackVisible = false
            }
            if (window.appSettingsOpen && normalizeSectionId(window.appSettingsSection) === "runtime" && !bridge.runtimeManagerBusy) {
                appSettingsWindow.refreshRuntimeManager()
            }
        }
        function onDataChanged() {
            if (window.appSettingsOpen && normalizeSectionId(window.appSettingsSection) === "runtime" && !bridge.runtimeManagerBusy) {
                appSettingsWindow.refreshRuntimeManager()
            }
        }
        function onRuntimeServerItemsChanged() {
            if (!appSettingsWindow.runtimeInstallOpen) {
                return
            }
            if (bridge.runtimeServerItemsService !== appSettingsWindow.runtimeManagerService) {
                return
            }
            appSettingsWindow.runtimeServerModel = bridge.runtimeServerItemsModel
        }
    }

    Timer {
        id: appSettingsFeedbackHideTimer
        interval: 2500
        repeat: false
        onTriggered: appSettingsWindow.appSettingsFeedbackVisible = false
    }

    FolderDialog {
        id: generateFolderDialog
        title: Strings.t("choose.default.project.folder")
        onAccepted: {
            var raw = selectedFolder.toString()
            if (raw.indexOf("file://") === 0) {
                raw = decodeURIComponent(raw.slice(7))
            }
            defaultProjectFolderField.text = raw
            if (generalSettingsPage.immediateApplyGeneral) {
                generalSettingsPage.queueGeneralSettingsSave()
            }
        }
    }

    Components.PageWindowFrame {
        moveWindow: appSettingsWindow
        bodyMargins: 20

        headerContent: Item {
            anchors.fill: parent

            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                text: appSettingsWindow.sectionDisplayLabel(window.appSettingsSection)
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
                        model: window.appSettingsSections
                        delegate: Components.TopIconTab {
                            required property int index
                            property var navItem: window.appSettingsSections[index]

                            label: navItem.label
                            selected: appSettingsWindow.normalizeSectionId(window.appSettingsSection) === navItem.id
                            iconSource: appSettingsWindow.settingsIconSource(navItem.icon, selected)
                            onClicked: window.appSettingsSection = navItem.id
                        }
                    }
                }
            }
        }

        StackLayout {
            id: settingsStack
            anchors.fill: parent
            currentIndex: appSettingsWindow.sectionIndex(window.appSettingsSection)
            onCurrentIndexChanged: appSettingsWindow.refreshSectionWindowHeight()

            AppearanceSettingsPage {
                id: appearanceSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            GeneralSettingsPage {
                id: generalSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
                generateFolderDialog: generateFolderDialog
            }

            PhpMyAdminSettingsPage {
                id: phpMyAdminSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            PhpSettingsPage {
                id: phpSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            NodeSettingsPage {
                id: nodeSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            RuntimeManagerPage {
                id: runtimeManagerPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            DatabaseSettingsPage {
                id: databaseSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            WebServerSettingsPage {
                id: webServerSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            RedisSettingsPage {
                id: redisSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }

            PortsSettingsPage {
                id: portsSettingsPage
                bridge: appSettingsWindow.bridge
                window: appSettingsWindow.window
                appSettingsWindow: appSettingsWindow
            }
        }
    }

    Dialogs.RuntimeInstallDialog {
        id: runtimeInstallWindow
        window: appSettingsWindow
        bridge: appSettingsWindow.bridge
        appSettingsWindow: appSettingsWindow
    }

}
