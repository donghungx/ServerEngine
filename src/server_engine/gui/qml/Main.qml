import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import QtQml
import "components" as Components
import "dialogs" as Dialogs
import "pages" as Pages
import "shell" as Shell
import "shell/mail" as Mail
import "shell/logs" as Logs
import "shell/redis" as Redis
import "settings" as Settings
import "theme"
import "i18n"

ApplicationWindow {
    id: window
    signal licenseDialogFinished(bool accepted)
    signal globalConfirmAccepted(string actionId, var payload)
    width: 1200
    height: 700
    minimumWidth: 1200
    minimumHeight: 700
    visible: true
    color: Theme.bg
    title: Strings.t("app.title")
    topPadding: 0
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0
    onClosing: function(closeEvent) {
        closeEvent.accepted = false
        window.hide()
    }

    property var bridge: dashboardBridge
    property bool appSettingsOpen: false
    property string appSettingsSection: "database"
    property string appSettingsInitialSection: ""
    property string appSettingsInitialRuntimeService: ""
    property bool defaultPortsConfirmOpen: false
    property bool globalConfirmOpen: false
    property string globalConfirmTitle: Strings.t("confirm")
    property string globalConfirmMessage: ""
    property string globalConfirmConfirmText: Strings.t("confirm")
    property string globalConfirmCancelText: Strings.t("cancel")
    property string globalConfirmActionId: ""
    property var globalConfirmPayload: ({})
    property var globalConfirmTransientParent: null
    property var appearanceAccentColors: [
        { name: "Blue", color: "#007bff" },
        { name: "Purple", color: "#894291" },
        { name: "Pink", color: "#e45c9c" },
        { name: "Red", color: "#ce4745" },
        { name: "Orange", color: "#e8883b" },
        { name: "Yellow", color: "#f7c84e" },
        { name: "Green", color: "#78b856" },
        { name: "Graphite", color: "#989898" }
    ]
    property var appSettingsSections: [
        { id: "general", label: Strings.t("general"), icon: "settings" },
        { id: "appearance", label: Strings.t("settings.appearance.title"), icon: "palette" },
        { id: "web", label: Strings.t("web.server"), icon: "server" },
        { id: "database", label: Strings.t("database"), icon: "database" },
        { id: "php", label: Strings.t("php"), icon: "code-xml" },
        { id: "phpmyadmin", label: Strings.t("phpmyadmin"), icon: "phpmyadmin" },
        { id: "node", label: Strings.t("node"), icon: "nodejs" },
        { id: "ports", label: Strings.t("ports"), icon: "network-ports" },
        { id: "runtime", label: Strings.t("runtime"), icon: "package" }
    ]
    property bool nodeInstallDialogOpen: false
    property bool nodeUninstallConfirmOpen: false
    property string nodeUninstallTargetHome: ""
    property string nodeUninstallTargetLabel: ""
    property bool runtimeSwitchConfirmOpen: false
    property string runtimeSwitchService: ""
    property string runtimeSwitchTarget: ""
    property string runtimeSwitchLabel: ""
    property bool runtimeSwitchServiceRunning: false
    property bool runtimeRemoveConfirmOpen: false
    property string runtimeRemoveService: ""
    property string runtimeRemoveTarget: ""
    property string runtimeRemoveLabel: ""
    property bool runtimeRemoveServiceRunning: false
    property bool runtimeInstallOpen: false
    property bool runtimeInstallOverwriteConfirmOpen: false
    property var runtimeInstallSelectedItem: ({})
    property bool aboutDialogOpen: false
    property string aboutVersion: ""
    property string aboutBuild: ""
    property string aboutRuntimeMode: ""
    property string aboutLicenseMode: ""
    property string aboutPythonVersion: ""
    property string aboutAppSupportPath: ""
    property string aboutLogoSource: ""
    property bool licenseDialogOpen: false
    property bool licenseDialogStartupEnforced: false
    property bool bottomTerminalOpen: false
    property bool bottomMailOpen: false
    property bool bottomLogsOpen: false
    property bool bottomRedisInspectorOpen: false
    property int bottomPanelHeight: bridge ? Math.max(80, Number(bridge.settingsBottomTerminalPanelHeight || 260)) : 260
    property bool mainWindowHasRestoreGeometry: false
    property real mainWindowRestoreX: 0
    property real mainWindowRestoreY: 0
    property real mainWindowRestoreWidth: 0
    property real mainWindowRestoreHeight: 0
    property string globalStatusMessage: Strings.t("app.status.stackHint")
    property string globalStatusDisplayMessage: Strings.t("app.status.stackHint")
    property bool globalStatusError: false
    property int globalStatusTick: 0
    property int globalStatusTypeIndex: 0
    property bool statusCursorVisible: true
    property alias websitePage: mainContentLayout.websitePage
    property alias databasePage: mainContentLayout.databasePage
    property alias databaseBackupPage: mainContentLayout.databaseBackupPage
    property string currentThemeMode: bridge ? String(bridge.settingsAppearanceTheme || "system").toLowerCase() : "system"
    property bool currentOsPrefersDark: bridge ? !!bridge.osPrefersDark : false
    property string currentAccentColor: bridge ? String(bridge.settingsAppearanceAccentColor || "#007bff").toLowerCase() : "#007bff"
    property string currentLanguage: bridge ? String(bridge.settingsAppearanceLanguage || "en").toLowerCase() : "en"
    property var navigationBackStack: []
    property var navigationForwardStack: []
    property var navigationCurrentState: ({ page: "home", backupDatabaseName: "" })
    property bool navigationSyncing: false
    property bool navigationInitialized: false
    readonly property bool canNavigateBack: navigationBackStack.length > 0
    readonly property bool canNavigateForward: navigationForwardStack.length > 0
    readonly property bool resolvedThemeDark: {
        var mode = String(window.currentThemeMode || "system").toLowerCase()
        if (mode === "dark") {
            return true
        }
        if (mode === "light") {
            return false
        }
        return !!window.currentOsPrefersDark
    }

    Binding {
        target: Theme
        property: "dark"
        value: window.resolvedThemeDark
    }
    Binding {
        target: Theme
        property: "accent"
        value: window.currentAccentColor
    }
    Binding {
        target: Theme
        property: "accentStrong"
        value: window.currentAccentColor
    }

    onAppSettingsSectionChanged: {
        if (appSettingsOpen && appSettingsSection === "runtime") {
            appSettingsWindow.refreshRuntimeManager()
        }
        if (appSettingsOpen) {
            Qt.callLater(function() {
                appSettingsWindow.applySectionWindowHeight(appSettingsSection)
            })
        }
    }

    onBridgeChanged: refreshThemeState()

    function openGlobalConfirm(titleText, messageText, actionId, payload, confirmText, cancelText, parentWindow) {
        window.globalConfirmTitle = String(titleText || Strings.t("confirm"))
        window.globalConfirmMessage = String(messageText || "")
        window.globalConfirmActionId = String(actionId || "")
        window.globalConfirmPayload = payload || ({})
        window.globalConfirmConfirmText = String(confirmText || Strings.t("confirm"))
        window.globalConfirmCancelText = String(cancelText || Strings.t("cancel"))
        window.globalConfirmTransientParent = parentWindow || null
        window.globalConfirmOpen = true
    }

    function closeGlobalConfirm() {
        window.globalConfirmOpen = false
        window.globalConfirmTransientParent = null
    }

    function firstDatabaseName() {
        var items = bridge.databaseItems || []
        return items.length > 0 ? String(items[0].name || "") : ""
    }

    function cloneNavigationState(state) {
        return {
            page: String(state && state.page ? state.page : "home"),
            backupDatabaseName: String(state && state.backupDatabaseName ? state.backupDatabaseName : "")
        }
    }

    function currentNavigationState() {
        return cloneNavigationState({
            page: bridge ? bridge.currentPage : "home",
            backupDatabaseName: bridge && String(bridge.currentPage || "") === "database-backup"
                ? databaseBackupPage.databaseName
                : ""
        })
    }

    function navigationStatesEqual(left, right) {
        return String(left.page || "") === String(right.page || "")
            && String(left.backupDatabaseName || "") === String(right.backupDatabaseName || "")
    }

    function commitNavigationState(nextState, pushHistory) {
        var normalized = cloneNavigationState(nextState)
        if (!navigationInitialized) {
            navigationCurrentState = normalized
            navigationInitialized = true
            return
        }
        if (navigationStatesEqual(navigationCurrentState, normalized)) {
            return
        }
        if (pushHistory) {
            navigationBackStack = navigationBackStack.concat([cloneNavigationState(navigationCurrentState)])
            navigationForwardStack = []
        }
        navigationCurrentState = normalized
    }

    function syncNavigationState() {
        if (navigationSyncing || !bridge) {
            return
        }
        navigationSyncing = true
        var nextState = currentNavigationState()
        navigationSyncing = false
        commitNavigationState(nextState, true)
    }

    function applyNavigationState(targetState) {
        var normalized = cloneNavigationState(targetState)
        navigationSyncing = true
        bridge.setCurrentPage(normalized.page)
        if (normalized.page === "database-backup") {
            databaseBackupPage.databaseName = normalized.backupDatabaseName
            databaseBackupPage.refreshBackupItems()
        }
        navigationCurrentState = normalized
        navigationSyncing = false
    }

    function navigateBack() {
        if (navigationBackStack.length === 0) {
            return
        }
        var previousState = navigationBackStack[navigationBackStack.length - 1]
        navigationBackStack = navigationBackStack.slice(0, -1)
        navigationForwardStack = navigationForwardStack.concat([cloneNavigationState(navigationCurrentState)])
        applyNavigationState(previousState)
    }

    function navigateForward() {
        if (navigationForwardStack.length === 0) {
            return
        }
        var nextState = navigationForwardStack[navigationForwardStack.length - 1]
        navigationForwardStack = navigationForwardStack.slice(0, -1)
        navigationBackStack = navigationBackStack.concat([cloneNavigationState(navigationCurrentState)])
        applyNavigationState(nextState)
    }

    function openNewPhpWebsite() {
        bridge.setCurrentPage("website")
        websitePage.projectTab = "php"
        websitePage.addSiteFeedback = ""
        websitePage.addSiteOpen = true
    }

    function openNewNodeProject() {
        bridge.setCurrentPage("website")
        websitePage.projectTab = "node"
        websitePage.editNodeProjectMode = false
        websitePage.addNodeProjectFeedback = ""
        websitePage.addNodeProjectFeedbackError = false
        websitePage.addNodeProjectOpen = true
    }

    function openNewDatabase() {
        bridge.setCurrentPage("database")
        bridge.refreshDatabaseRuntime()
        databasePage.newDatabasePopupOpen = true
    }

    function openDatabaseImport() {
        bridge.setCurrentPage("database")
        bridge.refreshDatabaseRuntime()
        databasePage.refreshDatabaseItems()
        databasePage.importDatabaseName = firstDatabaseName()
        databasePage.importPopupOpen = true
    }

    function openDatabaseBackup() {
        databaseBackupPage.databaseEngine = "mysql"
        databaseBackupPage.databaseName = firstDatabaseName()
        bridge.setCurrentPage("database-backup")
        databaseBackupPage.refreshBackupItems()
    }

    function openRuntimeSettings(serviceId) {
        appSettingsInitialSection = "runtime"
        appSettingsInitialRuntimeService = serviceId
        appSettingsOpen = true
        if (appSettingsWindow.visible) {
            appSettingsWindow.runtimeManagerService = serviceId
            appSettingsSection = "runtime"
            appSettingsWindow.refreshRuntimeManager()
            appSettingsWindow.applySectionWindowHeight(appSettingsSection)
        }
    }

    function openPhpSettings() {
        appSettingsInitialRuntimeService = ""
        appSettingsInitialSection = "php"
        appSettingsSection = "php"
        appSettingsOpen = true
        if (appSettingsWindow.visible) {
            appSettingsWindow.applySectionWindowHeight(appSettingsSection)
        }
    }

    function editSelectedWebsite() {
        bridge.setCurrentPage("website")
        websitePage.editSelectedWebsite()
    }

    function deleteSelectedWebsite() {
        bridge.setCurrentPage("website")
        websitePage.deleteSelectedWebsite()
    }

    function openSelectedWebsiteInBrowser() {
        bridge.setCurrentPage("website")
        websitePage.openSelectedWebsiteInBrowser()
        pushGlobalStatus("Opening selected website in browser...", false)
    }

    function revealSelectedWebsiteProject() {
        bridge.setCurrentPage("website")
        websitePage.revealSelectedWebsiteProject()
        pushGlobalStatus("Revealing selected website project in Finder...", false)
    }

    function copySelectedWebsiteLocalDomain() {
        bridge.setCurrentPage("website")
        websitePage.copySelectedWebsiteLocalDomain()
    }

    function generateSelectedWebsiteSelfSignedCertificate() {
        bridge.setCurrentPage("website")
        websitePage.generateSelectedWebsiteSelfSignedCertificate()
    }

    function reloadWebRoutes() {
        bridge.reloadWebRoutes()
    }

    function tailLogs() {
        bottomMailOpen = false
        bottomRedisInspectorOpen = false
        bottomTerminalOpen = false
        bottomLogsOpen = true
    }

    function openMailInbox() {
        bottomTerminalOpen = false
        bottomLogsOpen = false
        bottomRedisInspectorOpen = false
        bottomMailOpen = !bottomMailOpen
        if (bottomMailOpen) {
            Qt.callLater(bottomDock.requestRefreshMailbox)
        }
    }

    function openRedisInspector() {
        bottomTerminalOpen = false
        bottomLogsOpen = false
        bottomMailOpen = false
        bottomRedisInspectorOpen = !bottomRedisInspectorOpen
        if (bottomRedisInspectorOpen) {
            Qt.callLater(bottomDock.requestRefreshInspector)
        }
    }

    function openDefaultTerminal() {
        bottomLogsOpen = false
        bottomDock.beginExplicitSessionOpen()
        bottomTerminalOpen = true
        Qt.callLater(function() {
            bottomDock.openDefaultSession()
            bottomDock.finishExplicitSessionOpen()
        })
    }

    function openActiveDatabaseCli() {
        bottomDock.beginExplicitSessionOpen()
        bottomLogsOpen = false
        bottomTerminalOpen = true
        Qt.callLater(function() {
            bottomDock.openActiveDatabaseSession()
            bottomDock.finishExplicitSessionOpen()
        })
    }

    function openActiveMongodbCli() {
        bottomDock.beginExplicitSessionOpen()
        bottomLogsOpen = false
        bottomTerminalOpen = true
        Qt.callLater(function() {
            bottomDock.openActiveMongodbSession()
            bottomDock.finishExplicitSessionOpen()
        })
    }

    function openActivePostgresqlCli() {
        bottomDock.beginExplicitSessionOpen()
        bottomLogsOpen = false
        bottomTerminalOpen = true
        Qt.callLater(function() {
            bottomDock.openActivePostgresqlSession()
            bottomDock.finishExplicitSessionOpen()
        })
    }

    function openActiveRedisCli() {
        bottomMailOpen = false
        bottomLogsOpen = false
        bottomRedisInspectorOpen = false
        bottomDock.beginExplicitSessionOpen()
        bottomTerminalOpen = true
        Qt.callLater(function() {
            bottomDock.openActiveRedisSession()
            bottomDock.finishExplicitSessionOpen()
        })
    }

    function openWebsiteCli(siteData) {
        bottomDock.beginExplicitSessionOpen()
        bottomLogsOpen = false
        bottomTerminalOpen = true
        Qt.callLater(function() {
            bottomDock.openWebsiteSession(String(siteData.id || ""))
            bottomDock.finishExplicitSessionOpen()
        })
    }

    function openNodeProjectCli(nodeProjectData) {
        bottomDock.beginExplicitSessionOpen()
        bottomLogsOpen = false
        bottomTerminalOpen = true
        Qt.callLater(function() {
            bottomDock.openNodeProjectSession(String(nodeProjectData.id || ""))
            bottomDock.finishExplicitSessionOpen()
        })
    }

    function servicePortConflictBusy() {
        if (!bridge) {
            return false
        }
        var serviceId = String(bridge.servicePortConflictServiceId || "")
        if (serviceId === "web") {
            return !!bridge.stackActionBusy
        }
        if (serviceId === "database") {
            return !!bridge.databaseActionBusy
        }
        if (serviceId === "redis") {
            return !!bridge.redisActionBusy
        }
        if (serviceId === "memcached") {
            return !!bridge.memcachedActionBusy
        }
        if (serviceId === "mailpit") {
            return !!bridge.mailpitActionBusy
        }
        return false
    }

    function beginMainWindowMove() {
        if (!window.startSystemMove) {
            return
        }
        if (!window.active) {
            window.requestActivate()
        }
        window.startSystemMove()
    }

    function rememberMainWindowGeometry() {
        mainWindowHasRestoreGeometry = true
        mainWindowRestoreX = window.x
        mainWindowRestoreY = window.y
        mainWindowRestoreWidth = window.width
        mainWindowRestoreHeight = window.height
    }

    function toggleMainWindowMaximize() {
        if (window.visibility === Window.Maximized) {
            window.showNormal()
            if (mainWindowHasRestoreGeometry) {
                Qt.callLater(function() {
                    window.x = mainWindowRestoreX
                    window.y = mainWindowRestoreY
                    window.width = mainWindowRestoreWidth
                    window.height = mainWindowRestoreHeight
                })
            }
            return
        }
        rememberMainWindowGeometry()
        window.showMaximized()
    }

    function refreshThemeState() {
        if (!bridge) {
            return
        }
        window.currentThemeMode = String(bridge.settingsAppearanceTheme || "system").toLowerCase()
        window.currentOsPrefersDark = !!bridge.osPrefersDark
        window.currentAccentColor = String(bridge.settingsAppearanceAccentColor || "#007bff").toLowerCase()
        window.currentLanguage = String(bridge.settingsAppearanceLanguage || "en").toLowerCase()
        Strings.language = window.currentLanguage
    }

    function pushGlobalStatus(message, isError) {
        var next = String(message || "")
            .replace(/[\r\n]+/g, " ")
            .replace(/\s+/g, " ")
            .trim()
        if (next.length === 0) {
            return
        }
        if (next === globalStatusMessage && !!isError === !!globalStatusError) {
            return
        }
        if (bridge && bridge.logStatusBarMessage) {
            bridge.logStatusBarMessage(next, !!isError)
        }
        globalStatusMessage = next
        globalStatusError = !!isError
        if (bridge && bridge.showSystemStatusNotification) {
            bridge.showSystemStatusNotification(next, !!isError)
        }
        globalStatusTick = globalStatusTick + 1
    }

    function currentDatabaseStatus() {
        if (bridge.databaseBackupBusy) {
            var backupLabel = String(bridge.databaseBackupProgressLabel || "Working...")
            return { message: backupLabel, error: false }
        }
        if (String(bridge.databaseBackupMessage || "").trim().length > 0) {
            return {
                message: String(bridge.databaseBackupMessage || ""),
                error: !!bridge.databaseBackupError
            }
        }
        if (bridge.databaseImportBusy) {
            var importLabel = String(bridge.databaseImportJobTitle || bridge.databaseImportProgressLabel || "Working...")
            return { message: importLabel, error: false }
        }
        if (String(bridge.databaseImportMessage || "").trim().length > 0) {
            return {
                message: String(bridge.databaseImportMessage || ""),
                error: !!bridge.databaseImportError
            }
        }
        if (bridge.postgresqlBackupBusy) {
            return { message: String(bridge.postgresqlBackupProgressLabel || "Working..."), error: false }
        }
        if (String(bridge.postgresqlBackupMessage || "").trim().length > 0) {
            return {
                message: String(bridge.postgresqlBackupMessage || ""),
                error: !!bridge.postgresqlBackupError
            }
        }
        if (bridge.postgresqlImportBusy) {
            return { message: String(bridge.postgresqlImportProgressLabel || "Working..."), error: false }
        }
        if (String(bridge.postgresqlImportMessage || "").trim().length > 0) {
            return {
                message: String(bridge.postgresqlImportMessage || ""),
                error: !!bridge.postgresqlImportError
            }
        }
        if (bridge.mongodbBackupBusy) {
            return { message: String(bridge.mongodbBackupProgressLabel || "Working..."), error: false }
        }
        if (String(bridge.mongodbBackupMessage || "").trim().length > 0) {
            return {
                message: String(bridge.mongodbBackupMessage || ""),
                error: !!bridge.mongodbBackupError
            }
        }
        if (bridge.mongodbImportBusy) {
            return { message: String(bridge.mongodbImportProgressLabel || "Working..."), error: false }
        }
        if (String(bridge.mongodbImportMessage || "").trim().length > 0) {
            return {
                message: String(bridge.mongodbImportMessage || ""),
                error: !!bridge.mongodbImportError
            }
        }
        return {
            message: String(bridge.databaseRuntimeMessage || ""),
            error: !!bridge.databaseRuntimeError
        }
    }

    onGlobalStatusTickChanged: {
        globalStatusTypeIndex = 0
        globalStatusDisplayMessage = ""
        statusTypeTimer.restart()
    }

    Timer {
        id: statusTypeTimer
        interval: 24
        repeat: true
        running: false
        onTriggered: {
            if (window.globalStatusTypeIndex >= window.globalStatusMessage.length) {
                stop()
                return
            }
            window.globalStatusTypeIndex += 1
            window.globalStatusDisplayMessage = window.globalStatusMessage.slice(0, window.globalStatusTypeIndex)
        }
    }

    Timer {
        id: statusCursorBlinkTimer
        interval: 380
        repeat: true
        running: statusTypeTimer.running
        onTriggered: window.statusCursorVisible = !window.statusCursorVisible
    }

    function hasRuntimeDownloadLicense() {
        var status = bridge ? bridge.licenseStatus() : ({})
        var state = String(status.status || "")
        return Boolean(status.valid) && (state === "active" || state === "trial")
    }

    function startRequiredRuntimeBootstrapIfLicensed() {
        if (hasRuntimeDownloadLicense()) {
            bridge.ensureRequiredRuntimesAtStartup()
        }
    }

    Component.onCompleted: {
        if (hasRuntimeDownloadLicense()) {
            bridge.ensureRequiredRuntimesAtStartup()
        } else {
            // Runtime downloads require an active license or trial. Show this
            // before any runtime manifest/download request is started.
            licenseDialogStartupEnforced = true
            licenseDialogOpen = true
        }
        navigationCurrentState = currentNavigationState()
        navigationInitialized = true
    }

    onLicenseDialogFinished: function(accepted) {
        if (accepted) {
            startRequiredRuntimeBootstrapIfLicensed()
        }
    }

    Connections {
        target: bridge
        function onCurrentPageChanged() {
            window.syncNavigationState()
        }
        function onOperationFeedbackChanged() {
            var opMessage = String(bridge.lastOperationMessage || "").trim()
            if (opMessage.length > 0) {
                window.pushGlobalStatus(opMessage, bridge.lastOperationError)
                return
            }
            var nodeMessage = String(bridge.nodeProjectRuntimeMessage || "").trim()
            if (nodeMessage.length > 0) {
                window.pushGlobalStatus(nodeMessage, bridge.nodeProjectRuntimeError)
            }
        }
        function onStackFeedbackChanged() {
            window.pushGlobalStatus(bridge.stackFeedbackMessage, bridge.stackFeedbackError)
        }
        function onDatabaseRuntimeFeedbackChanged() {
            if (bridge.databaseAnyJobBusy) {
                var dbBusyStatus = window.currentDatabaseStatus()
                var nextDbBusyMessage = String(dbBusyStatus.message || "").replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim()
                var nextDbBusyError = !!dbBusyStatus.error
                if (nextDbBusyMessage.length === 0 || (nextDbBusyMessage === globalStatusMessage && nextDbBusyError === globalStatusError)) {
                    return
                }
                globalStatusMessage = nextDbBusyMessage
                globalStatusError = nextDbBusyError
                globalStatusTick = globalStatusTick + 1
                return
            }
            var dbStatus = window.currentDatabaseStatus()
            window.pushGlobalStatus(dbStatus.message, dbStatus.error)
        }
        function onPostgresqlRuntimeFeedbackChanged() {
            if (bridge.databaseAnyJobBusy) {
                var pgBusyStatus = window.currentDatabaseStatus()
                var nextPgBusyMessage = String(pgBusyStatus.message || "").replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim()
                var nextPgBusyError = !!pgBusyStatus.error
                if (nextPgBusyMessage.length === 0 || (nextPgBusyMessage === globalStatusMessage && nextPgBusyError === globalStatusError)) {
                    return
                }
                globalStatusMessage = nextPgBusyMessage
                globalStatusError = nextPgBusyError
                globalStatusTick = globalStatusTick + 1
                return
            }
            var pgStatus = window.currentDatabaseStatus()
            window.pushGlobalStatus(pgStatus.message, pgStatus.error)
        }
        function onMongodbRuntimeFeedbackChanged() {
            if (bridge.databaseAnyJobBusy) {
                var mongoBusyStatus = window.currentDatabaseStatus()
                var nextMongoBusyMessage = String(mongoBusyStatus.message || "").replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim()
                var nextMongoBusyError = !!mongoBusyStatus.error
                if (nextMongoBusyMessage.length === 0 || (nextMongoBusyMessage === globalStatusMessage && nextMongoBusyError === globalStatusError)) {
                    return
                }
                globalStatusMessage = nextMongoBusyMessage
                globalStatusError = nextMongoBusyError
                globalStatusTick = globalStatusTick + 1
                return
            }
            var mongoStatus = window.currentDatabaseStatus()
            window.pushGlobalStatus(mongoStatus.message, mongoStatus.error)
        }
        function onRedisRuntimeFeedbackChanged() {
            if (String(bridge.currentPage || "") === "cache") {
                window.pushGlobalStatus(bridge.memcachedRuntimeMessage, bridge.memcachedRuntimeError)
            } else {
                window.pushGlobalStatus(bridge.redisRuntimeMessage, bridge.redisRuntimeError)
            }
        }
        function onMailpitRuntimeFeedbackChanged() {
            window.pushGlobalStatus(bridge.mailpitRuntimeMessage, bridge.mailpitRuntimeError)
        }
    }

    Connections {
        target: databasePage
        function onBackupRequested(rowData) {
            console.log(
                "[Main] databasePage.onBackupRequested name=",
                String(rowData && rowData.name ? rowData.name : "")
            )
            bridge.clearDatabaseRuntimeFeedback()
            var nextDatabaseName = String(rowData && rowData.name ? rowData.name : "")
            databaseBackupPage.databaseName = nextDatabaseName
            bridge.setCurrentPage("database-backup")
            bridge.refreshDatabaseBackupItemsAsync(nextDatabaseName)
        }
    }

    Shell.TitleBar {
        id: nativeTitleRow
        topPadding: window.topPadding
        dashboardBridge: bridge
        appWindow: window
        onAppSettingsRequested: appSettingsOpen = true
        onMoveRequested: window.beginMainWindowMove()
        onMaximizeToggleRequested: window.toggleMainWindowMaximize()
    }

    Shell.MainContent {
        id: mainContentLayout
        dashboardBridge: bridge
        bottomPanelItem: bottomDock
        onInstallNodeRuntimeRequested: window.openRuntimeSettings("node")
        onInstallPhpRuntimeRequested: window.openRuntimeSettings("php")
        onOpenPhpSettingsRequested: window.openPhpSettings()
        onOpenDatabaseCliRequested: window.openActiveDatabaseCli()
        onOpenRedisCliRequested: window.openActiveRedisCli()
        onOpenBottomMailRequested: window.openMailInbox()
        onOpenMongodbCliRequested: window.openActiveMongodbCli()
        onOpenPostgresqlCliRequested: window.openActivePostgresqlCli()
        onOpenPostgresqlBackupRequested: function(rowData) {
            databaseBackupPage.databaseEngine = "postgresql"
            databaseBackupPage.databaseName = String(rowData && rowData.name ? rowData.name : "")
            bridge.setCurrentPage("database-backup")
            databaseBackupPage.refreshBackupItems()
        }
        onOpenWebsiteCliRequested: function(siteData) {
            window.openWebsiteCli(siteData)
        }
        onOpenNodeProjectCliRequested: function(nodeProjectData) {
            window.openNodeProjectCli(nodeProjectData)
        }
    }

    Shell.StatusBar {
        id: statusBar
        dashboardBridge: window.bridge
        globalStatusError: window.globalStatusError
        globalStatusDisplayMessage: window.globalStatusDisplayMessage
        statusCursorVisible: window.statusCursorVisible
        bottomTerminalOpen: window.bottomTerminalOpen
        bottomMailOpen: window.bottomMailOpen
        bottomLogsOpen: window.bottomLogsOpen
        bottomRedisInspectorOpen: window.bottomRedisInspectorOpen
        statusTypeTimer: statusTypeTimer
        onToggleBottomTerminalRequested: {
            window.bottomMailOpen = false
            window.bottomRedisInspectorOpen = false
            window.bottomTerminalOpen = !window.bottomTerminalOpen
            if (window.bottomTerminalOpen) {
                window.bottomLogsOpen = false
                Qt.callLater(bottomDock.ensureDefaultSession)
            }
        }
        onToggleBottomMailRequested: window.openMailInbox()
        onToggleBottomLogsRequested: {
            window.bottomMailOpen = false
            window.bottomRedisInspectorOpen = false
            window.bottomLogsOpen = !window.bottomLogsOpen
            if (window.bottomLogsOpen) {
                window.bottomTerminalOpen = false
            }
        }
        onToggleBottomRedisInspectorRequested: window.openRedisInspector()
    }

    Shell.BottomDock {
        id: bottomDock
        terminalBackend: appTerminalController
        bottomTerminalOpen: window.bottomTerminalOpen
        bottomMailOpen: window.bottomMailOpen
        bottomLogsOpen: window.bottomLogsOpen
        bottomRedisInspectorOpen: window.bottomRedisInspectorOpen
        statusBarItem: statusBar
        appWindow: window
        dashboardBridge: bridge
        onCloseAllRequested: {
            window.bottomTerminalOpen = false
            window.bottomMailOpen = false
            window.bottomLogsOpen = false
            window.bottomRedisInspectorOpen = false
        }
    }


    Settings.AppSettingsWindow {
        id: appSettingsWindow
        window: window
        bridge: window.bridge
    }

    Dialogs.RuntimeSwitchConfirmDialog {
        id: runtimeSwitchConfirmWindow
        window: window
        bridge: window.bridge
    }

    Dialogs.RuntimeRemoveConfirmDialog {
        id: runtimeRemoveConfirmWindow
        window: window
        bridge: window.bridge
    }

    Dialogs.RequiredRuntimeBootstrapDialog {
        id: requiredRuntimeBootstrapWindow
        bridge: window.bridge
    }

    Dialogs.RuntimeInstallDialog {
        id: runtimeInstallWindow
        window: window
        bridge: window.bridge
        appSettingsWindow: appSettingsWindow
    }

    Dialogs.ServicePortConflictDialog {
        id: servicePortConflictWindow
        window: window
        bridge: window.bridge
    }

    Dialogs.RuntimeOverwriteConfirmDialog {
        id: runtimeInstallOverwriteConfirmWindow
        window: window
        bridge: window.bridge
    }

    Dialogs.NodeUninstallConfirmDialog {
        id: nodeUninstallConfirmWindow
        window: window
        bridge: window.bridge
    }

    Dialogs.NodeInstallDialog {
        id: nodeInstallDialog
        window: window
        bridge: window.bridge
    }

    Dialogs.DefaultPortsConfirmDialog {
        id: defaultPortsConfirmWindow
        window: window
        appSettingsWindow: appSettingsWindow
    }

    Dialogs.GlobalConfirmWindow {
        id: globalConfirmWindow
        window: window
        titleText: window.globalConfirmTitle
        messageText: window.globalConfirmMessage
        confirmText: window.globalConfirmConfirmText
        cancelText: window.globalConfirmCancelText
        confirmActionId: window.globalConfirmActionId
        confirmPayload: window.globalConfirmPayload
        transientParent: window.globalConfirmTransientParent || window
        onConfirmed: function(actionId, payload) {
            window.globalConfirmAccepted(actionId, payload)
            window.globalConfirmOpen = false
            window.globalConfirmActionId = ""
            window.globalConfirmPayload = ({})
            window.globalConfirmTransientParent = null
        }
        onCanceled: {
            window.globalConfirmOpen = false
            window.globalConfirmActionId = ""
            window.globalConfirmPayload = ({})
            window.globalConfirmTransientParent = null
        }
    }

    Dialogs.AboutDialog {
        id: aboutDialog
        window: window
    }

    Dialogs.LicenseDialog {
        id: licenseDialog
        window: window
        bridge: window.bridge
    }
}
