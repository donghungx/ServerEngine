import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Qt.labs.platform as Native
import "../components" as Components
import "../dialogs" as Dialogs
import "../modals" as Modals
import "../theme"
import "../website_add_site_presets.js" as SitePresets
import "website" as WebsiteParts
import "../i18n"

Components.ShellCard {
    id: root
    required property var dashboardBridge
    signal installNodeRuntimeRequested()
    signal websiteCliRequested(var siteData)
    signal nodeProjectCliRequested(var nodeProjectData)
    border.width: 0
    color: "transparent"

    property bool addSiteOpen: false
    property bool addNodeProjectOpen: false
    property bool addProxyOpen: false
    property string editingProxyId: ""
    property var editingProxyData: ({})
    property bool editNodeProjectMode: false
    property string nodeProjectDialogSection: "configuration"
    property bool apacheWebServerPopupOpen: false
    property bool nginxWebServerPopupOpen: false
    property string projectTab: "php"
    property var apacheModulesDraft: []
    property var apacheRuntimeModel: []
    property var nginxRuntimeModel: []
    property string apacheConfigDraft: ""
    property string apacheConfigFeedback: ""
    property string nginxConfigDraft: ""
    property string nginxConfigFeedback: ""
    property string apachePortDraft: "8080"
    property string apachePortLoaded: "8080"
    property string nginxPortDraft: "8080"
    property string nginxPortLoaded: "8080"
    property string apacheErrorLogPathDraft: ""
    property string nginxWorkerProcessesDraft: "1"
    property string nginxWorkerConnectionsDraft: "1024"
    property string nginxKeepaliveTimeoutDraft: "65"
    property string nginxClientMaxBodySizeDraft: "64m"
    property bool nginxSendfileDraft: true
    property bool nginxGzipDraft: true
    property bool nginxServerTokensDraft: false
    property string nginxErrorLogPathDraft: ""
    property string addSiteFeedback: ""
    property bool addSiteFeedbackError: false
    property bool projectPathError: false
    property string projectPathErrorMessage: ""
    property bool addSiteBusy: false
    property bool addSiteCreationFailed: false
    property bool addSiteCreationSucceeded: false
    property string addSiteCreationErrorMessage: ""
    property int addSiteFailedPhaseIndex: -1
    property int createSiteLabelWidth: 170
    property int webServerStatusRevision: 0
    property int addSiteTemplateIndex: 0
    property string addSiteProjectBasePath: "~/ServerEngine"
    property int wordpressDownloadProgress: 0
    property string wordpressDownloadStatus: ""
    property string laravelCompatibilityMessage: ""
    property bool laravelCompatibilityError: false
    property var wordpressSetupStages: [
        "Validating input...",
        "Downloading WordPress archive...",
        "Extracting WordPress files...",
        "Configuring wp-config.php...",
        "Creating database...",
        "Creating site and generating web server config...",
        "Reloading web server route...",
        "Installing WordPress database tables...",
        "Site created."
    ]
    property var laravelSetupStages: [
        "Validating input...",
        "Preparing Laravel installer...",
        "Creating Laravel project with Composer...",
        "Writing Laravel .env database settings...",
        "Creating database...",
        "Creating site and generating web server config...",
        "Reloading web server route...",
        "Site created."
    ]
    property var composerSetupStages: [
        "Validating input...",
        "Preparing Composer project...",
        "Creating project with Composer...",
        "Composer project ready...",
        "Creating database...",
        "Creating site and generating web server config...",
        "Reloading web server route...",
        "Site created."
    ]
    property var basicSetupStages: [
        "Validating input...",
        "Preparing project folder...",
        "Preparing site...",
        "Creating site and generating web server config...",
        "Reloading web server route...",
        "Site created."
    ]
    property var existingSetupStages: [
        "Validating input...",
        "Preparing existing project...",
        "Creating site and generating web server config...",
        "Generating SSL certificate...",
        "Reloading web server route...",
        "Site created."
    ]
    property var pendingAddSitePayload: ({})
    property var addSiteDirectoryChoices: ["/"]
    property string addNodeProjectFeedback: ""
    property bool addNodeProjectFeedbackError: false
    property string editingNodeProjectId: ""
    property var nodeProjectToDelete: ({})
    readonly property int nodeTableContentWidth: 950
    property bool siteDetailsOpen: false
    property var selectedSite: ({})
    property string selectedSiteSection: "domain"
    property var siteToDelete: ({})

    readonly property var domainField: addSiteWindow ? addSiteWindow.domainField : null
    readonly property var notesField: addSiteWindow ? addSiteWindow.notesField : null
    readonly property var projectPathField: addSiteWindow ? addSiteWindow.projectPathField : null
    readonly property var runningDirectoryCombo: addSiteWindow ? addSiteWindow.runningDirectoryCombo : null
    readonly property var phpVersionCombo: addSiteWindow ? addSiteWindow.phpVersionCombo : null
    readonly property var wordpressVersionCombo: addSiteWindow ? addSiteWindow.wordpressVersionCombo : null
    readonly property var wordpressUsernameField: addSiteWindow ? addSiteWindow.wordpressUsernameField : null
    readonly property var wordpressPasswordField: addSiteWindow ? addSiteWindow.wordpressPasswordField : null
    readonly property var wordpressDatabasePrefixField: addSiteWindow ? addSiteWindow.wordpressDatabasePrefixField : null
    readonly property var wordpressDatabaseNameField: addSiteWindow ? addSiteWindow.wordpressDatabaseNameField : null
    readonly property var laravelVersionCombo: addSiteWindow ? addSiteWindow.laravelVersionCombo : null
    readonly property var laravelCreateDatabaseCheckbox: addSiteWindow ? addSiteWindow.laravelCreateDatabaseCheckbox : null
    readonly property var laravelDatabaseNameField: addSiteWindow ? addSiteWindow.laravelDatabaseNameField : null
    readonly property var sslCheckbox: addSiteWindow ? addSiteWindow.sslCheckbox : null
    readonly property var starterCheckbox: addSiteWindow ? addSiteWindow.starterCheckbox : null
    property string siteFilterQuery: ""
    property var siteSections: [
        { id: "domain", label: Strings.t("domain") },
        { id: "directory", label: Strings.t("directory") },
        { id: "url.rewrite", label: Strings.t("url.rewrite") },
        { id: "default", label: Strings.t("default") },
        { id: "config", label: Strings.t("config") },
        { id: "php.version", label: Strings.t("php.version") },
        { id: "response.log", label: Strings.t("response.log") }
    ]
    readonly property var visibleSiteSections: {
        if (!dashboardBridge || dashboardBridge.settingsWebServer === "nginx") {
            return siteSections
        }
        return siteSections.filter(function(item) { return item.id !== "url.rewrite" })
    }
    readonly property bool canAddPhpSite: {
        if (!dashboardBridge) {
            return false
        }
        var _rev = webServerStatusRevision
        return dashboardBridge.webServerRunning()
    }
    readonly property var filteredWebsiteItems: {
        if (!dashboardBridge) {
            return []
        }
        var allItems = dashboardBridge.websiteItems || []
        if (siteFilterQuery.length === 0) {
            return allItems
        }
        return allItems.filter(function(item) {
            var values = [
                String(item.primary_domain || ""),
                String(item.name || ""),
                String(item.notes || item.note || item.remark || item.remarks || ""),
                String(item.project_path || "")
            ]
            var domains = item.domains || []
            for (var i = 0; i < domains.length; i++) {
                values.push(String(domains[i] || ""))
            }
            var haystack = values.join(" ").toLowerCase()
            return haystack.indexOf(siteFilterQuery) !== -1
        })
    }

    function databaseNameFromDomain(domain) {
        return domain.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 48)
    }

    function randomWordPressDatabaseName() {
        var token = Math.random().toString(36).slice(2, 8)
        var stamp = Date.now().toString(36).slice(-4)
        return "wp_" + token + "_" + stamp
    }

    function folderNameFromDomain(domain) {
        return root.sanitizeLocalDomain(domain).replace(/^-+|-+$/g, "")
    }

    function sanitizeLocalDomain(domain) {
        return String(domain || "").toLowerCase().replace(/[^a-z0-9.-]/g, "")
    }

    function isValidLocalDomain(domain) {
        return /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/.test(String(domain || "").trim())
    }

    function updateWordPressProjectPath() {
        if ((root.addSiteTemplateIndex !== 1 && root.addSiteTemplateIndex !== 2) || !projectPathField) {
            return
        }
        var folderName = root.folderNameFromDomain(domainField.text)
        if (folderName.length === 0) {
            projectPathField.text = root.addSiteProjectBasePath
            return
        }
        var base = String(root.addSiteProjectBasePath || dashboardBridge.settingsDefaultProjectFolder || "~/ServerEngine").replace(/\/+$/g, "")
        projectPathField.text = base + "/" + folderName
        if (dashboardBridge.pathExists(projectPathField.text)) {
            root.addSiteFeedback = "Project folder already exists. Choose a different domain or base folder."
            root.addSiteFeedbackError = true
        } else if (root.addSiteFeedbackError) {
            root.addSiteFeedback = ""
            root.addSiteFeedbackError = false
        }
    }

    function siteNameFromDomain(domain) {
        return domain.split(".")[0]
    }

    function addSitePayload() {
        var domain = domainField.text.trim()
        var template = addSiteWindow && addSiteWindow.selectedTemplateConfig
            ? addSiteWindow.selectedTemplateConfig
            : ({})
        var isWordPress = root.addSiteTemplateIndex === 1 || template.mode === "wordpress"
        var isLaravel = root.addSiteTemplateIndex === 2 || template.mode === "laravel"
        var isComposer = template.mode === "composer"
        var createDb = isWordPress || (isLaravel ? laravelCreateDatabaseCheckbox.checked : Boolean(template.createDatabase))
        var frameworkPreset = String(template.frameworkPreset || (isWordPress ? "wordpress" : (isLaravel ? "laravel" : "custom")))
        var webRoot = String(template.webRoot || (isWordPress ? "." : (isLaravel ? "public" : (runningDirectoryCombo.currentText === "/" ? "." : runningDirectoryCombo.currentText))))
        return {
            name: root.siteNameFromDomain(domain),
            local_domain: domain,
            project_path: projectPathField.text.trim(),
            web_root: webRoot,
            php_version: phpVersionCombo.currentText,
            ssl_enabled: sslCheckbox.checked,
            ssl_enforce_tls: false,
            ssl_allow_http: true,
            database_enabled: createDb,
            database_name: createDb ? (isWordPress ? wordpressDatabaseNameField.text.trim() : (isLaravel ? laravelDatabaseNameField.text.trim() : root.databaseNameFromDomain(domain))) : "",
            database_user: createDb ? "root" : "",
            notes: notesField.text.trim(),
            create_starter: !isWordPress && !isLaravel && starterCheckbox.checked,
            framework_preset: frameworkPreset,
            composer_package: isComposer ? String(template.composerPackage || "") : "",
            template_choice: addSiteWindow && addSiteWindow.selectedTemplateChoice
                ? String(addSiteWindow.selectedTemplateChoice)
                : "",
            laravel_version: isLaravel ? laravelVersionCombo.currentText : "",
            wordpress_version: isWordPress ? wordpressVersionCombo.currentText : "",
            wordpress_admin_user: isWordPress ? wordpressUsernameField.text.trim() : "",
            wordpress_admin_password: isWordPress ? wordpressPasswordField.text : "",
            wordpress_database_prefix: isWordPress ? wordpressDatabasePrefixField.text.trim() : ""
        }
    }

    function syncLaravelPhpCompatibility(autoSelectPhp) {
        if (!dashboardBridge || !laravelVersionCombo || !phpVersionCombo) {
            return
        }
        if (root.addSiteTemplateIndex !== 2) {
            root.laravelCompatibilityMessage = ""
            root.laravelCompatibilityError = false
            return
        }
        var info = dashboardBridge.laravelVersionCompatibility(
            String(laravelVersionCombo.currentText || ""),
            String(phpVersionCombo.currentText || "")
        )
        var recommended = String(info.recommended_php || "")
        if (autoSelectPhp && recommended.length > 0 && String(phpVersionCombo.currentText || "") !== recommended) {
            var idx = phpVersionCombo.find(recommended)
            if (idx >= 0) {
                phpVersionCombo.currentIndex = idx
                info = dashboardBridge.laravelVersionCompatibility(
                    String(laravelVersionCombo.currentText || ""),
                    String(phpVersionCombo.currentText || "")
                )
            }
        }
        root.laravelCompatibilityMessage = String(info.message || "")
        root.laravelCompatibilityError = !Boolean(info.compatible)
    }

    function resetAddSiteDialog() {
        root.addSiteFeedback = ""
        root.addSiteFeedbackError = false
        root.addSiteBusy = false
        root.projectPathError = false
        root.projectPathErrorMessage = ""
        root.addSiteTemplateIndex = 0
        root.addSiteProjectBasePath = dashboardBridge.settingsDefaultProjectFolder || "~/ServerEngine"
        root.wordpressDownloadProgress = 0
        root.wordpressDownloadStatus = ""
        root.pendingAddSitePayload = ({})
        wordpressVersionCombo.currentIndex = 0
        wordpressUsernameField.text = "admin"
        wordpressPasswordField.text = ""
        wordpressDatabasePrefixField.text = "wp_"
        wordpressDatabaseNameField.text = root.randomWordPressDatabaseName()
        starterCheckbox.checked = false
        laravelCreateDatabaseCheckbox.checked = false
        laravelVersionCombo.currentIndex = 0
        laravelDatabaseNameField.text = root.databaseNameFromDomain(domainField.text.trim())
        projectPathField.text = ""
        root.laravelCompatibilityMessage = ""
        root.laravelCompatibilityError = false
    }

    function finishAddSiteWithPayload(payload) {
        if (dashboardBridge.createSite(payload)) {
            root.addSiteFeedback = ""
            root.addSiteFeedbackError = false
            root.addSiteOpen = false
        } else {
            root.addSiteFeedback = dashboardBridge.lastOperationMessage.length > 0
                ? dashboardBridge.lastOperationMessage
                : Strings.t("create.site.failed")
            root.addSiteFeedbackError = true
            root.addSiteBusy = false
        }
    }

    function folderPathFromUrl(folderUrl) {
        var value = folderUrl.toString()
        if (value.indexOf("file://") === 0) {
            return decodeURIComponent(value.slice(7))
        }
        return value
    }

    function refreshApacheConfigDraft() {
        root.apacheConfigDraft = String(dashboardBridge.activeApacheConfigContent || "")
        root.apacheConfigFeedback = ""
        root.apachePortDraft = String(dashboardBridge.settingsWebPort || "8080")
        root.apachePortLoaded = root.apachePortDraft
        root.apacheRuntimeModel = dashboardBridge.webServerRuntimeItems("apache")
        root.apacheModulesDraft = dashboardBridge.apacheModuleItems
        root.apacheErrorLogPathDraft = dashboardBridge.settingsApacheErrorLogPath
    }

    function refreshNginxConfigDraft() {
        root.nginxConfigDraft = String(dashboardBridge.activeNginxConfigContent || "")
        root.nginxConfigFeedback = ""
        root.nginxPortDraft = String(dashboardBridge.settingsWebPort || "8080")
        root.nginxPortLoaded = root.nginxPortDraft
        root.nginxRuntimeModel = dashboardBridge.webServerRuntimeItems("nginx")
    }

    function normalizePhpVersionToken(value) {
        return String(value || "").replace(/^php/i, "").replace(/[^0-9]/g, "")
    }

    function applyDefaultPhpVersionSelection() {
        if (!dashboardBridge || !phpVersionCombo) {
            return
        }
        var defaultPhp = String(dashboardBridge.settingsDefaultPhpVersion || "")
        if (defaultPhp.length === 0) {
            return
        }
        var idx = phpVersionCombo.find(defaultPhp)
        if (idx >= 0) {
            phpVersionCombo.currentIndex = idx
            return
        }

        var normalizedDefault = normalizePhpVersionToken(defaultPhp)
        for (var i = 0; i < phpVersionCombo.count; i++) {
            var itemText = phpVersionCombo.textAt(i)
            if (normalizePhpVersionToken(itemText) === normalizedDefault) {
                phpVersionCombo.currentIndex = i
                return
            }
        }

        var noPrefix = String(defaultPhp).replace(/^php/i, "")
        var majorMinor = noPrefix.split(".").slice(0, 2).join(".")
        if (majorMinor.length > 0) {
            for (var j = 0; j < phpVersionCombo.count; j++) {
                var text = String(phpVersionCombo.textAt(j))
                if (text === majorMinor || text.indexOf(majorMinor + ".") === 0) {
                    phpVersionCombo.currentIndex = j
                    return
                }
            }
        }
    }

    function refreshAddSiteDirectoryChoices() {
        if (!dashboardBridge || !projectPathField) {
            addSiteDirectoryChoices = ["/"]
            return
        }
        var path = projectPathField.text.trim()
        var choices = dashboardBridge.siteDirectoryChoices(path)
        if (!choices || choices.length === 0) {
            choices = ["/"]
        }
        addSiteDirectoryChoices = choices
        if (runningDirectoryCombo.currentIndex < 0) {
            runningDirectoryCombo.currentIndex = 0
        }
    }

    function nodeDomainExists(domainValue) {
        var domain = String(domainValue || "").trim().toLowerCase()
        if (domain.length === 0) {
            return false
        }
        for (var i = 0; i < dashboardBridge.websiteItems.length; i++) {
            var item = dashboardBridge.websiteItems[i]
            if (String(item.primary_domain || "").toLowerCase() === domain) {
                return true
            }
            var domains = item.domains || []
            for (var j = 0; j < domains.length; j++) {
                if (String(domains[j] || "").toLowerCase() === domain) {
                    return true
                }
            }
        }
        for (var k = 0; k < dashboardBridge.nodeProjectItems.length; k++) {
            var nodeItem = dashboardBridge.nodeProjectItems[k]
            if (String(nodeItem.id || "") !== root.editingNodeProjectId
                && String(nodeItem.domain || "").toLowerCase() === domain) {
                return true
            }
        }
        return false
    }

    function domainExists(domainValue) {
        var domain = String(domainValue || "").trim().toLowerCase()
        if (domain.length === 0 || !dashboardBridge) {
            return false
        }
        if (root.nodeDomainExists(domain)) {
            return true
        }
        var proxies = dashboardBridge.proxyItems || []
        for (var i = 0; i < proxies.length; i++) {
            if (String(proxies[i].id || "") !== root.editingProxyId
                && String(proxies[i].local_domain || "").toLowerCase() === domain) {
                return true
            }
        }
        return false
    }

    function syncSelectedSiteFromBridge() {
        if (!root.selectedSite || !root.selectedSite.id || !dashboardBridge) {
            return
        }
        for (var i = 0; i < dashboardBridge.websiteItems.length; i++) {
            var item = dashboardBridge.websiteItems[i]
            if (item.id === root.selectedSite.id) {
                root.selectedSite = item
                return
            }
        }
    }

    function selectedWebsiteAvailable() {
        return !!root.selectedSite && String(root.selectedSite.id || "").length > 0
    }

    function selectedWebsiteDomain() {
        if (!selectedWebsiteAvailable()) {
            return ""
        }
        return String(root.selectedSite.primary_domain || root.selectedSite.local_domain || root.selectedSite.name || "")
    }

    function siteSectionLabel(sectionId) {
        for (var i = 0; i < siteSections.length; i++) {
            if (siteSections[i].id === sectionId) {
                return siteSections[i].label
            }
        }
        return String(sectionId || "")
    }

    function editSelectedWebsite() {
        if (!selectedWebsiteAvailable()) {
            dashboardBridge.reportNoSelectedWebsite()
            return
        }
        root.projectTab = "php"
        root.selectedSiteSection = "domain"
        root.siteDetailsOpen = true
    }

    function deleteSelectedWebsite() {
        if (!selectedWebsiteAvailable()) {
            dashboardBridge.reportNoSelectedWebsite()
            return
        }
        root.siteToDelete = root.selectedSite
        deleteSiteDialog.visible = true
        deleteSiteDialog.raise()
        deleteSiteDialog.requestActivate()
    }

    function openSelectedWebsiteInBrowser() {
        if (!selectedWebsiteAvailable()) {
            dashboardBridge.reportNoSelectedWebsite()
            return
        }
        Qt.openUrlExternally(String(root.selectedSite.browse_url || "http://" + selectedWebsiteDomain()))
    }

    function revealSelectedWebsiteProject() {
        if (!selectedWebsiteAvailable()) {
            dashboardBridge.reportNoSelectedWebsite()
            return
        }
        dashboardBridge.revealInFinder(String(root.selectedSite.project_path || ""))
    }

    function copySelectedWebsiteLocalDomain() {
        dashboardBridge.copyTextToClipboard(selectedWebsiteDomain())
    }

    function generateSelectedWebsiteSelfSignedCertificate() {
        if (!selectedWebsiteAvailable()) {
            dashboardBridge.reportNoSelectedWebsite()
            return
        }
        dashboardBridge.createSiteSelfSignedCertificate(String(root.selectedSite.id))
        root.syncSelectedSiteFromBridge()
    }

    function ensureSelectedSiteSectionSupported() {
        if (!dashboardBridge) {
            return
        }
        if (dashboardBridge.settingsWebServer !== "nginx" && root.selectedSiteSection === "url.rewrite") {
            root.selectedSiteSection = "domain"
        }
        if (root.selectedSiteSection === "ssl") {
            root.selectedSiteSection = "domain"
        }
    }

    onSelectedSiteChanged: {
        root.ensureSelectedSiteSectionSupported()
        if (siteDetailsWindow.siteSectionItem) {
            siteDetailsWindow.siteSectionItem.siteData = selectedSite
            try {
                siteDetailsWindow.siteSectionItem.dashboardBridge = dashboardBridge
            } catch (error) {
            }
        }
    }

    Connections {
        target: dashboardBridge
        function onDataChanged() {
            root.webServerStatusRevision += 1
            root.syncSelectedSiteFromBridge()
            root.ensureSelectedSiteSectionSupported()
        }
        function onAppSettingsFeedbackChanged() {
            root.webServerStatusRevision += 1
            root.ensureSelectedSiteSectionSupported()
        }
        function onSiteCreationProgressChanged(value, message) {
            if (!root.addSiteBusy) {
                return
            }
            root.wordpressDownloadProgress = value
            root.wordpressDownloadStatus = message
        }
        function onSiteCreationCompleted(success, message) {
            if (!root.addSiteBusy) {
                return
            }
            addSiteWindow.closeConfirmOpen = false
            if (success) {
                root.resetAddSiteDialog()
                root.addSiteOpen = false
                return
            }
            root.addSiteBusy = false
            root.addSiteFeedback = message && message.length > 0 ? message : Strings.t("create.site.failed")
            root.addSiteFeedbackError = true
        }
        function onNodeProjectRuntimeActionCompleted(success) {
            editNodeProjectWindow.refreshNodeRuntime()
            if (dashboardBridge.nodeProjectRuntimeMessage.length > 0) {
                root.addNodeProjectFeedback = dashboardBridge.nodeProjectRuntimeMessage
                root.addNodeProjectFeedbackError = dashboardBridge.nodeProjectRuntimeError
            }
        }
        function onNodeProjectSaveCompleted(success) {
            root.addNodeProjectFeedback = dashboardBridge.lastOperationMessage
            root.addNodeProjectFeedbackError = dashboardBridge.lastOperationError
            if (!success) {
                return
            }
            if (root.editNodeProjectMode) {
                editNodeProjectWindow.refreshNodeProjectDetails()
            }
            if (addNodeProjectWindow.closeOnNodeSaveSuccess) {
                addNodeProjectWindow.closeOnNodeSaveSuccess = false
                root.addNodeProjectOpen = false
            }
            if (editNodeProjectWindow.closeOnNodeSaveSuccess) {
                editNodeProjectWindow.closeOnNodeSaveSuccess = false
                root.editNodeProjectMode = false
                root.editingNodeProjectId = ""
            }
        }
    }

    function siteSectionSource(sectionLabel) {
        switch (sectionLabel) {
        case "domain":
            return Qt.resolvedUrl("../dialogs/site_details/DomainManagerSection.qml")
        case "directory":
            return Qt.resolvedUrl("../dialogs/site_details/DirectorySection.qml")
        case "url.rewrite":
            return Qt.resolvedUrl("../dialogs/site_details/UrlRewriteSection.qml")
        case "default":
            return Qt.resolvedUrl("../dialogs/site_details/DefaultDocumentSection.qml")
        case "config":
            return Qt.resolvedUrl("../dialogs/site_details/ConfigSection.qml")
        case "ssl":
            return Qt.resolvedUrl("../dialogs/site_details/SslSection.qml")
        case "php.version":
            return Qt.resolvedUrl("../dialogs/site_details/PhpVersionSection.qml")
        case "response.log":
            return Qt.resolvedUrl("../dialogs/site_details/ResponseLogSection.qml")
        default:
            return Qt.resolvedUrl("../dialogs/site_details/DirectorySection.qml")
        }
    }

    function siteSectionIcon(sectionLabel) {
        switch (sectionLabel) {
        case "directory":
            return "folder-cog"
        case "domain":
            return "globe-check"
        case "url.rewrite":
            return "globe"
        case "default":
            return "panel-top"
        case "config":
            return "file-sliders"
        case "ssl":
            return "shield-check"
        case "php.version":
            return "code-xml"
        case "response.log":
            return "activity"
        default:
            return "settings"
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 64
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        spacing: 14

        Row {
            id: tabRow
            width: parent.width
            spacing: 8

            Components.AppRadioButton {
                id: phpProjectButton
                text: Strings.t("php.project")
                checked: root.projectTab === "php"

                onClicked: root.projectTab = "php"
            }

            Components.AppRadioButton {
                id: nodeProjectButton
                text: Strings.t("node.project")
                checked: root.projectTab === "node"

                onClicked: root.projectTab = "node"
            }

            Components.AppRadioButton {
                id: proxyButton
                text: "Proxy Project"
                checked: root.projectTab === "proxy"

                onClicked: root.projectTab = "proxy"
            }

        }

        RowLayout {
            id: actionRow
            width: parent.width
            spacing: 10

            Components.AppButton {
                text: root.projectTab === "php" ? Strings.t("add.site") : (root.projectTab === "proxy" ? "Add Proxy Project" : Strings.t("add.project"))
                iconSource: "icons/lucide/plus.svg"
                enabled: root.projectTab !== "php" || root.canAddPhpSite
                opacity: enabled ? 1 : 0.5

                onClicked: {
                    if (root.projectTab === "php") {
                        if (!root.canAddPhpSite) {
                            root.addSiteFeedback = Strings.t("start.apache.or.nginx.before.adding.a.php.site")
                            root.addSiteFeedbackError = true
                            return
                        }
                        root.addSiteOpen = true
                    } else {
                        if (root.projectTab === "proxy") {
                            root.editingProxyId = ""
                            root.editingProxyData = ({})
                            root.addProxyOpen = true
                            return
                        }
                        root.editNodeProjectMode = false
                        root.editingNodeProjectId = ""
                        root.addNodeProjectOpen = true
                    }
                }
            }

            Components.AppButton {
                text: root.projectTab === "php"
                    ? dashboardBridge.currentWebServerLabel
                    : (Strings.t("node") + " " + (dashboardBridge.settingsNodeVersion.length > 0 ? dashboardBridge.settingsNodeVersion : Strings.t("not.selected")))
                visible: root.projectTab === "php"
                iconSource: "icons/lucide/settings.svg"

                enabled: root.projectTab === "php"

                onClicked: {
                    if (dashboardBridge.settingsWebServer === "apache") {
                        root.refreshApacheConfigDraft()
                        root.apacheWebServerPopupOpen = true
                    } else {
                        root.refreshNginxConfigDraft()
                        root.nginxWebServerPopupOpen = true
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Components.AppTextField {
                id: siteFilterField
                Layout.preferredWidth: 300
                placeholderText: Strings.t("domain.or.remarks")
                selectByMouse: true
                onTextChanged: root.siteFilterQuery = String(text || "").trim().toLowerCase()
            }
        }

        Item {
            width: parent.width
            height: Math.max(0, parent.height - tabRow.implicitHeight - actionRow.implicitHeight - 28)

            WebsiteParts.WebsitePhpTable {
                anchors.fill: parent
                visible: root.projectTab === "php"
                pageRoot: root
                deleteSiteDialog: deleteSiteDialog
            }

            WebsiteParts.WebsiteNodeTable {
                anchors.fill: parent
                visible: root.projectTab === "node"
                pageRoot: root
                dashboardBridge: dashboardBridge
                editNodeProjectWindow: editNodeProjectWindow
                deleteNodeProjectDialog: deleteNodeProjectDialog
            }

            ColumnLayout {
                anchors.fill: parent
                visible: root.projectTab === "proxy"
                spacing: 14

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Theme.surfaceAlt
                    border.color: Theme.border
                    radius: Theme.radius
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 0
                        Text { text: "Domain"; color: Theme.muted; font.pixelSize: 12; Layout.preferredWidth: 280 }
                        Text { text: "Target"; color: Theme.muted; font.pixelSize: 12; Layout.fillWidth: true }
                        Text { text: "Actions"; color: Theme.muted; font.pixelSize: 12; Layout.preferredWidth: 260 }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: dashboardBridge.proxyItems
                    delegate: Components.ShellCard {
                        required property var modelData
                        width: ListView.view.width
                        height: 78
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 14
                            Text {
                                Layout.preferredWidth: 280
                                text: modelData.local_domain
                                color: Theme.accentStrong
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.target
                                color: Theme.muted
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                            }
                            RowLayout {
                                Layout.preferredWidth: 260
                                spacing: 6
                                Components.QuickActionButton {
                                    text: "Open"
                                    iconSource: "../icons/lucide/external-link.svg"
                                    tooltip: "Open website"
                                    onClicked: Qt.openUrlExternally("http://" + modelData.local_domain)
                                }
                                Components.QuickActionButton {
                                    text: "Copy"
                                    iconSource: "../icons/lucide/file.svg"
                                    tooltip: "Copy domain"
                                    onClicked: dashboardBridge.copyTextToClipboard(modelData.local_domain)
                                }
                                Components.QuickActionButton {
                                    text: "Modify"
                                    iconSource: "../icons/lucide/settings.svg"
                                    tooltip: "Modify proxy"
                                    onClicked: {
                                        root.editingProxyId = String(modelData.id || "")
                                        root.editingProxyData = modelData
                                        root.addProxyOpen = true
                                    }
                                }
                                Components.QuickActionButton {
                                    text: "Delete"
                                    iconSource: "../icons/lucide/trash-2.svg"
                                    tooltip: "Delete proxy"
                                    danger: true
                                    onClicked: dashboardBridge.deleteProxy(modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Modals.WebsiteAddSiteModal {
        id: addSiteWindow
        root: root
    }

    Modals.NodeProjectCreateModal {
        id: addNodeProjectWindow
        pageRoot: root
    }

    WebsiteParts.ProxyProjectAddWindow {
        id: addProxyProjectWindow
        root: root
        proxyId: root.editingProxyId
        proxyData: root.editingProxyData
    }

    WebsiteParts.NodeProjectWindow {
        id: editNodeProjectWindow
        root: root
    }

    Dialogs.ApacheWebServerDialog {
        id: apacheWebServerWindow
        root: root
    }

    Dialogs.NginxWebServerDialog {
        id: nginxWebServerWindow
        root: root
    }

    Dialogs.WebsiteSiteDetailsDialog {
        id: siteDetailsWindow
        root: root
    }

    WebsiteParts.DeleteNodeProjectDialog {
        id: deleteNodeProjectDialog
        root: root
        dashboardBridge: dashboardBridge
    }

    Dialogs.WebsiteDeleteSiteDialog {
        id: deleteSiteDialog
        root: root
    }

}
