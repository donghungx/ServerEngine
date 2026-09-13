import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"
import "./node_project_templates/ExistingProject.js" as ExistingProjectTemplate
import "./node_project_templates/ReactTemplate.js" as ReactTemplate
import "./node_project_templates/NextTemplate.js" as NextTemplate
import "./node_project_templates/RemixTemplate.js" as RemixTemplate
import "./node_project_templates/VueTemplate.js" as VueTemplate
import "./node_project_templates/NuxtTemplate.js" as NuxtTemplate
import "./node_project_templates/SvelteTemplate.js" as SvelteTemplate
import "./node_project_templates/SvelteKitTemplate.js" as SvelteKitTemplate
import "./node_project_templates/ExpressTemplate.js" as ExpressTemplate
import "./node_project_templates/FastifyTemplate.js" as FastifyTemplate
import "./node_project_templates/NestTemplate.js" as NestTemplate

Window {
    id: root

    required property var pageRoot
    readonly property var dashboardBridge: pageRoot ? pageRoot.dashboardBridge : null

    property int wizardStep: 0
    property bool existingProjectMode: false
    property string selectedTemplateId: ""
    property string localDomain: ""
    property string projectBasePath: ""
    property string projectFolder: ""
    property string nodeVersion: ""
    property string nodeRunCommandText: ""
    property string port: ""
    property string notes: ""
    property bool useSsl: false
    property bool useRandomPort: true
    property var nodeRunScriptItems: []
    property string existingProjectValidationText: ""
    property bool existingProjectValidationError: false
    property string folderDialogMode: ""
    property bool createProjectBusy: false
    property int createProjectProgress: 0
    property string createProjectStatus: ""
    property int createProjectStageIndex: -1
    property bool createProjectSuccess: false
    property var createProjectStages: []

    readonly property var templates: [
        ExistingProjectTemplate.template(),
        ReactTemplate.template(),
        NextTemplate.template(),
        RemixTemplate.template(),
        VueTemplate.template(),
        NuxtTemplate.template(),
        SvelteTemplate.template(),
        SvelteKitTemplate.template(),
        ExpressTemplate.template(),
        FastifyTemplate.template(),
        NestTemplate.template()
    ]

    visible: pageRoot && pageRoot.addNodeProjectOpen
    width: 720
    height: 520
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: ""
    color: "transparent"
    modality: Qt.WindowModal
    transientParent: pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.FramelessWindowHint

    onVisibleChanged: {
        if (visible) {
            raise()
            requestActivate()
            Qt.callLater(root.resetWizard)
        }
    }

    onClosing: function(closeEvent) {
        closeEvent.accepted = true
        root.closeModal()
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        context: Qt.WindowShortcut
        onActivated: root.closeModal()
    }

    Connections {
        target: dashboardBridge

        function onNodeProjectSaveProgressChanged(progress, message) {
            if (root.wizardStep === 3) {
                root.updateCreateProjectProgress(progress, message)
            }
        }

        function onNodeProjectSaveCompleted(success) {
            if (root.wizardStep !== 3) {
                return
            }
            root.finishCreateProjectFlow(success, dashboardBridge ? dashboardBridge.nodeProjectSaveStatus : "")
        }
    }

    function templateById(templateId) {
        for (var i = 0; i < templates.length; i++) {
            if (String(templates[i].id || "") === String(templateId || "")) {
                return templates[i]
            }
        }
        return null
    }

    function createProjectStagesForTemplate(templateId) {
        var template = templateById(templateId) || ({})
        var stages = [
            "Validating project data",
            "Creating project files"
        ]
        if (String(template.installCommand || "").trim().length > 0) {
            stages.push("Installing node_modules")
        }
        stages.push(
            "Saving project mapping",
            "Writing web server configuration",
            "Reloading web server routes",
            "Project ready to run"
        )
        return stages
    }

    function defaultPortFor(templateId) {
        if (templateId === "express" || templateId === "fastify") {
            return "3001"
        }
        if (templateId === "vue" || templateId === "svelte") {
            return "5173"
        }
        return "3000"
    }

    function randomPortForTemplate(templateId, currentPort) {
        var fallbackPort = parseInt(defaultPortFor(templateId), 10)
        var candidatePort = parseInt(currentPort, 10)
        var startPort = !isNaN(candidatePort) && candidatePort > 0 ? candidatePort + 1 : fallbackPort + 1
        if (!dashboardBridge || !dashboardBridge.nextAvailableNodePort) {
            return String(isNaN(startPort) ? 3000 : startPort)
        }
        var nextPort = dashboardBridge.nextAvailableNodePort(isNaN(startPort) ? 3000 : startPort)
        return String(nextPort || (isNaN(startPort) ? 3000 : startPort))
    }

    function sanitizeLocalDomain(domain) {
        return String(domain || "").toLowerCase().replace(/[^a-z0-9.-]/g, "")
    }

    function isValidLocalDomain(domain) {
        return /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/.test(String(domain || "").trim())
    }

    function folderNameFromDomain(domain) {
        var value = String(domain || "").toLowerCase()
        var firstLabel = value.split(".")[0] || ""
        return firstLabel.replace(/[^a-z0-9]/g, "")
    }

    function latestNodeVersion() {
        if (!dashboardBridge || !dashboardBridge.nodeRuntimeVersions || dashboardBridge.nodeRuntimeVersions.length === 0) {
            return ""
        }
        return String(dashboardBridge.nodeRuntimeVersions[dashboardBridge.nodeRuntimeVersions.length - 1] || "")
    }

    function parseVersionParts(version) {
        var raw = String(version || "").trim().replace(/^v/i, "")
        if (raw.length === 0) {
            return [0, 0, 0]
        }
        var parts = raw.split(".")
        var major = parseInt(parts[0], 10)
        var minor = parts.length > 1 ? parseInt(parts[1], 10) : 0
        var patch = parts.length > 2 ? parseInt(parts[2], 10) : 0
        return [
            isNaN(major) ? 0 : major,
            isNaN(minor) ? 0 : minor,
            isNaN(patch) ? 0 : patch
        ]
    }

    function compareVersions(a, b) {
        var left = parseVersionParts(a)
        var right = parseVersionParts(b)
        for (var i = 0; i < 3; i++) {
            if (left[i] > right[i]) {
                return 1
            }
            if (left[i] < right[i]) {
                return -1
            }
        }
        return 0
    }

    function versionAtLeast(version, minimumVersion) {
        if (String(minimumVersion || "").length === 0) {
            return true
        }
        return compareVersions(version, minimumVersion) >= 0
    }

    function nodeVersionsForTemplate(templateId) {
        var template = templateById(templateId)
        var versions = dashboardBridge && dashboardBridge.nodeRuntimeVersions ? dashboardBridge.nodeRuntimeVersions : []
        if (!template || String(template.minNodeVersion || "").length === 0) {
            return versions
        }
        var filtered = []
        for (var i = 0; i < versions.length; i++) {
            var version = String(versions[i] || "")
            if (versionAtLeast(version, template.minNodeVersion)) {
                filtered.push(version)
            }
        }
        return filtered
    }

    function preferredNodeVersionForTemplate(templateId) {
        var template = templateById(templateId)
        var versions = nodeVersionsForTemplate(templateId)
        if (template && String(template.recommendedNodeVersion || "").length > 0) {
            for (var i = 0; i < versions.length; i++) {
                if (String(versions[i] || "") === String(template.recommendedNodeVersion || "")) {
                    return String(versions[i] || "")
                }
            }
        }
        return versions.length > 0 ? String(versions[versions.length - 1] || "") : ""
    }

    function runScriptsForTemplate(templateId) {
        if (templateId === "existing") {
            return [
                { label: "npm run dev", name: "dev", command: "npm run dev", port: "3000" },
                { label: "npm start", name: "start", command: "npm start", port: "3000" }
            ]
        }
        if (templateId === "next" || templateId === "remix" || templateId === "nest") {
            return [
                { label: "npm run dev", name: "dev", command: "npm run dev", port: "3000" },
                { label: "npm start", name: "start", command: "npm start", port: "3000" }
            ]
        }
        if (templateId === "svelte" || templateId === "sveltekit" || templateId === "vue" || templateId === "nuxt") {
            return [
                { label: "npm run dev", name: "dev", command: "npm run dev", port: defaultPortFor(templateId) },
                { label: "npm start", name: "start", command: "npm start", port: defaultPortFor(templateId) }
            ]
        }
        return [
            { label: "npm run dev", name: "dev", command: "npm run dev", port: defaultPortFor(templateId) },
            { label: "npm start", name: "start", command: "npm start", port: defaultPortFor(templateId) }
        ]
    }

    function folderPathFromUrl(folderUrl) {
        var value = String(folderUrl || "")
        if (value.indexOf("file://") === 0) {
            return decodeURIComponent(value.slice(7))
        }
        return value
    }

    function slugFromTemplate(templateId) {
        return String(templateId || "project")
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/^-+|-+$/g, "")
    }

    function applyTemplateDefaults(templateId) {
        selectedTemplateId = templateId
        createProjectStages = createProjectStagesForTemplate(templateId)
        existingProjectMode = false
        folderDialogMode = ""
        localDomain = ""
        projectBasePath = ""
        var baseFolder = dashboardBridge && dashboardBridge.settingsDefaultProjectFolder
            ? String(dashboardBridge.settingsDefaultProjectFolder)
            : "~/ServerEngine"
        projectBasePath = baseFolder
        projectFolder = ""
        nodeVersion = preferredNodeVersionForTemplate(templateId)
        port = randomPortForTemplate(templateId, port)
        notes = ""
        useSsl = true
        useRandomPort = true
        nodeRunScriptItems = []
        nodeRunCommandText = ""
        existingProjectValidationText = ""
        existingProjectValidationError = false
        updateTemplateProjectFolder()
        syncFormFields()
    }

    function startExistingProjectFlow() {
        existingProjectMode = true
        selectedTemplateId = "existing"
        createProjectStages = createProjectStagesForTemplate("existing")
        nodeVersion = latestNodeVersion()
        folderDialogMode = "existing"
        existingProjectValidationText = ""
        existingProjectValidationError = false
    }

    function finishExistingProjectFlow(folderPath) {
        var cleanFolder = String(folderPath || "")
        projectFolder = cleanFolder
        projectBasePath = ""
        localDomain = ""
        nodeVersion = latestNodeVersion()
        port = defaultPortFor("existing")
        notes = ""
        useSsl = false
        useRandomPort = false
        existingProjectMode = false
        folderDialogMode = ""
        wizardStep = 1
        nodeRunScriptItems = runScriptsForTemplate("existing")
        nodeRunCommandText = nodeRunScriptItems.length > 0 ? String(nodeRunScriptItems[0].command || "") : ""
        existingProjectValidationText = ""
        existingProjectValidationError = false
        syncFormFields()
    }

    function resetWizard() {
        wizardStep = 0
        existingProjectMode = false
        selectedTemplateId = ""
        createProjectStages = createProjectStagesForTemplate("existing")
        localDomain = ""
        projectBasePath = ""
        projectFolder = ""
        nodeVersion = ""
        nodeRunCommandText = ""
        port = ""
        notes = ""
        useSsl = false
        useRandomPort = true
        nodeRunScriptItems = []
        existingProjectValidationText = ""
        existingProjectValidationError = false
        folderDialogMode = ""
        createProjectBusy = false
        createProjectProgress = 0
        createProjectStatus = ""
        createProjectStageIndex = -1
        createProjectSuccess = false
        syncFormFields()
    }

    function updateTemplateProjectFolder() {
        if (selectedTemplateId === "existing") {
            return
        }
        var basePath = String(projectBasePath || "").trim()
        var domain = sanitizeLocalDomain(localDomain).trim()
        if (domain !== localDomain) {
            localDomain = domain
        }
        if (basePath.length === 0 || domain.length === 0) {
            projectFolder = ""
            existingProjectValidationText = ""
            existingProjectValidationError = false
            return
        }
        var folderName = folderNameFromDomain(domain)
        if (folderName.length === 0) {
            projectFolder = ""
            existingProjectValidationText = "Project folder name must contain letters or numbers."
            existingProjectValidationError = true
            return
        }
        var cleanedBase = basePath.replace(/\/+$/g, "")
        projectFolder = cleanedBase + "/" + folderName
        if (dashboardBridge && dashboardBridge.pathExists && dashboardBridge.pathExists(projectFolder)) {
            existingProjectValidationText = "Project folder already exists."
            existingProjectValidationError = true
            return
        }
        existingProjectValidationText = ""
        existingProjectValidationError = false
    }

    function inspectExistingProjectFolder(folderUrl) {
        var selectedPath = folderPathFromUrl(folderUrl).trim()
        if (selectedPath.length === 0) {
            existingProjectValidationText = "Project path is required."
            existingProjectValidationError = true
            return false
        }
        var result = dashboardBridge && dashboardBridge.inspectNodeProject
            ? dashboardBridge.inspectNodeProject(selectedPath)
            : ({ valid: false, message: "This is not a Node project.", scripts: [], port: "" })
        if (!result || !result.valid) {
            existingProjectValidationText = String(result && result.message ? result.message : "This is not a Node project.")
            existingProjectValidationError = true
            return false
        }
        projectFolder = selectedPath
        nodeVersion = latestNodeVersion()
        nodeRunScriptItems = result.scripts || []
        nodeRunCommandText = String(result.script || "")
        port = String(result.port || defaultPortFor("existing"))
        existingProjectValidationText = ""
        existingProjectValidationError = false
        existingProjectMode = false
        wizardStep = 1
        syncFormFields()
        return true
    }

    function syncFormFields() {
        if (typeof localDomainField !== "undefined") {
            localDomainField.text = localDomain
        }
        if (typeof templateLocalDomainField !== "undefined") {
            templateLocalDomainField.text = localDomain
        }
        if (typeof projectFolderField !== "undefined") {
            projectFolderField.text = projectFolder
        }
        if (typeof templateProjectFolderField !== "undefined") {
            templateProjectFolderField.text = projectFolder
        }
        if (typeof portField !== "undefined") {
            portField.text = port
        }
        if (typeof templatePortField !== "undefined") {
            templatePortField.text = port
        }
        if (typeof notesField !== "undefined") {
            notesField.text = notes
        }
        if (typeof templateNotesField !== "undefined") {
            templateNotesField.text = notes
        }
        if (typeof nodeRunOptionsCombo !== "undefined" && nodeRunOptionsCombo) {
            var runIndex = -1
            for (var i = 0; i < nodeRunScriptItems.length; i++) {
                if (String(nodeRunScriptItems[i].command || "") === String(nodeRunCommandText || "")) {
                    runIndex = i
                    break
                }
            }
            nodeRunOptionsCombo.currentIndex = runIndex >= 0 ? runIndex : (nodeRunScriptItems.length > 0 ? 0 : -1)
        }
        if (typeof sslCheckbox !== "undefined") {
            sslCheckbox.checked = useSsl
        }
        if (typeof templateSslCheckbox !== "undefined") {
            templateSslCheckbox.checked = useSsl
        }
        if (typeof templateRandomPortCheckbox !== "undefined") {
            templateRandomPortCheckbox.checked = useRandomPort
        }
    }

    function currentFormIsValid() {
        if (createProjectBusy) {
            return false
        }
        if (wizardStep === 1) {
            return localDomain.trim().length > 0
                && projectFolder.trim().length > 0
                && nodeVersion.length > 0
                && nodeRunScriptItems.length > 0
                && port.trim().length > 0
        }
        if (wizardStep === 2) {
            if (!isValidLocalDomain(localDomain)) {
                return false
            }
            if (projectBasePath.trim().length === 0 || projectFolder.trim().length === 0) {
                return false
            }
            if (existingProjectValidationError) {
                return false
            }
            if (nodeVersion.length === 0) {
                return false
            }
            if (!useRandomPort) {
                return port.trim().length > 0
                    && /^[0-9]+$/.test(port.trim())
            }
            return true
        }
        return false
    }

    function updateCreateProjectProgress(progress, message) {
        createProjectProgress = Math.max(0, Math.min(Number(progress || 0), 100))
        createProjectStatus = String(message || "")
        if (createProjectStatus.indexOf("Validating project data") === 0) {
            createProjectStageIndex = 0
        } else if (createProjectStatus.indexOf("Creating project files") === 0) {
            createProjectStageIndex = 1
        } else if (createProjectStatus.indexOf("Installing node_modules") === 0 || createProjectStatus.indexOf("node_modules installed") === 0) {
            createProjectStageIndex = 2
        } else if (createProjectStatus.indexOf("Saving project mapping") === 0) {
            createProjectStageIndex = 3
        } else if (createProjectStatus.indexOf("Writing web server configuration") === 0) {
            createProjectStageIndex = 4
        } else if (createProjectStatus.indexOf("Reloading web server routes") === 0) {
            createProjectStageIndex = 5
        } else if (createProjectProgress >= 95) {
            createProjectStageIndex = createProjectStages.length - 1
        } else {
            createProjectStageIndex = 0
        }
        createProjectBusy = createProjectProgress < 100
    }

    function startCreateProjectFlow() {
        createProjectBusy = true
        createProjectSuccess = false
        createProjectProgress = 1
        createProjectStageIndex = 0
        createProjectStatus = "Validating project data..."
        wizardStep = 3
    }

    function finishCreateProjectFlow(success, message) {
        createProjectBusy = false
        createProjectSuccess = success
        createProjectProgress = success ? 100 : createProjectProgress
        createProjectStageIndex = success ? createProjectStages.length : createProjectStageIndex
        createProjectStatus = String(message || (success ? "Project ready to run." : "Project creation failed."))
    }

    function closeModal() {
        if (pageRoot) {
            pageRoot.addNodeProjectOpen = false
        }
    }

    function requestNodeRuntimeInstall() {
        if (pageRoot && pageRoot.installNodeRuntimeRequested) {
            pageRoot.installNodeRuntimeRequested()
        }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 20
        color: Theme.surface
        clip: true

        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 24
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) {
                root.startSystemMove()
                mouse.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: root.wizardStep === 3
                    ? "Creating project..."
                    : (root.wizardStep === 0
                    ? "Choose a template for your new project:"
                    : (root.wizardStep === 1
                        ? "Choose options for your existing project:"
                        : "Choose options for your new project:")
                    )
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.wizardStep

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: -20
                        anchors.rightMargin: -20
                        height: 1
                        color: Theme.border
                    }

                    GridLayout {
                        id: chooserGrid
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 14
                        columns: 5
                        columnSpacing: 14
                        rowSpacing: 0
                        property int cellWidth: Math.floor((width - (columnSpacing * 4)) / 5)
                        height: implicitHeight + 14

                        Repeater {
                            model: root.templates

                            delegate: Item {
                                required property var modelData
                                Layout.preferredWidth: chooserGrid.cellWidth
                                Layout.minimumWidth: chooserGrid.cellWidth
                                Layout.maximumWidth: chooserGrid.cellWidth
                                Layout.preferredHeight: 106
                                Layout.minimumHeight: 106
                                Layout.maximumHeight: 106

                                readonly property bool selected: root.selectedTemplateId === modelData.id

                                Column {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: 0
                                    spacing: 4

                                    Item {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 66
                                        height: 66

                                        Rectangle {
                                            visible: selected
                                            anchors.fill: parent
                                            radius: 14
                                            color: Theme.accentStrong
                                            opacity: 0.08
                                        }

                                        Image {
                                            id: iconImage
                                            anchors.centerIn: parent
                                            width: 36
                                            height: 36
                                            sourceSize.width: 72
                                            sourceSize.height: 72
                                            source: modelData.icon
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            visible: false
                                        }

                                        MultiEffect {
                                            anchors.centerIn: parent
                                            width: 36
                                            height: 36
                                            source: iconImage
                                            colorization: 1.0
                                            colorizationColor: Theme.accentStrong
                                            brightness: 1.0
                                        }
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(112, titleText.implicitWidth + 16)
                                        height: 26
                                        radius: 10
                                        color: selected ? Theme.accentStrong : "transparent"

                                        Text {
                                            id: titleText
                                            anchors.centerIn: parent
                                            text: modelData.title
                                            color: selected ? "white" : Theme.text
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.NoWrap
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: templateMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.id === "existing") {
                                            root.selectedTemplateId = "existing"
                                            root.existingProjectValidationText = ""
                                            root.existingProjectValidationError = false
                                            return
                                        }
                                        root.applyTemplateDefaults(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: -20
                        anchors.rightMargin: -20
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.border
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                id: existingFormColumn
                                anchors.centerIn: parent
                                width: Math.min(560, parent.width)
                                spacing: 12

                                Components.SettingsLabeledControl {
                                    title: "Local domain"
                                    titleWidth: 160
                                    Components.AppTextField {
                                        id: localDomainField
                                        Layout.fillWidth: true
                                        text: root.localDomain
                                        placeholderText: "my-app.engine"
                                        onTextEdited: {
                                            var cleaned = root.sanitizeLocalDomain(text)
                                            if (cleaned !== text) {
                                                text = cleaned
                                            }
                                            root.localDomain = cleaned
                                        }
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    title: "Project folder"
                                    titleWidth: 160
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Components.AppTextField {
                                            id: projectFolderField
                                            Layout.fillWidth: true
                                            text: root.projectFolder
                                            placeholderText: "~/ServerEngine/my-app"
                                            readOnly: true
                                        }

                                        Components.AppButton {
                                            text: Strings.t("choose")
                                            onClicked: {
                                                root.existingProjectMode = true
                                                root.folderDialogMode = "existing"
                                                folderDialog.open()
                                            }
                                        }
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    title: "Node version"
                                    titleWidth: 160
                                    Components.AppComboBox {
                                        id: nodeVersionCombo
                                        Layout.fillWidth: true
                                        model: dashboardBridge ? dashboardBridge.nodeRuntimeVersions : []
                                        currentIndex: {
                                            var versions = dashboardBridge && dashboardBridge.nodeRuntimeVersions ? dashboardBridge.nodeRuntimeVersions : []
                                            if (versions.length === 0) {
                                                return -1
                                            }
                                            var selectedIndex = find(root.nodeVersion)
                                            if (selectedIndex >= 0) {
                                                return selectedIndex
                                            }
                                            return versions.length - 1
                                        }
                                        onCurrentIndexChanged: {
                                            if (currentIndex >= 0 && currentIndex < (model ? model.length : 0)) {
                                                root.nodeVersion = currentText
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: !dashboardBridge || dashboardBridge.nodeRuntimeVersions.length === 0
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 168
                                    text: Strings.t("no.node.runtime.installed.a.href.install.node.install.one.in.runtime.manager.a")
                                    textFormat: Text.RichText
                                    linkColor: Theme.accentStrong
                                    color: Theme.muted
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    onLinkActivated: function(_link) { root.requestNodeRuntimeInstall() }
                                }

                                Text {
                                    visible: dashboardBridge && dashboardBridge.nodeRuntimeVersions.length > 0
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 168
                                    text: "<a href='install-more'>Install more</a>"
                                    textFormat: Text.RichText
                                    linkColor: Theme.accentStrong
                                    color: Theme.muted
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    onLinkActivated: function(_link) { root.requestNodeRuntimeInstall() }
                                }

                                Components.SettingsLabeledControl {
                                    title: "Run options"
                                    titleWidth: 160
                                    Components.AppComboBox {
                                        id: nodeRunOptionsCombo
                                        Layout.fillWidth: true
                                        model: root.nodeRunScriptItems
                                        textRole: "label"
                                        onCurrentIndexChanged: {
                                            if (currentIndex < 0 || currentIndex >= root.nodeRunScriptItems.length) {
                                                root.nodeRunCommandText = ""
                                                return
                                            }
                                            var selected = root.nodeRunScriptItems[currentIndex] || {}
                                            if (String(selected.port || "").length > 0) {
                                                portField.text = String(selected.port)
                                            }
                                            root.nodeRunCommandText = String(selected.command || "")
                                        }
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    title: "Port"
                                    titleWidth: 160
                                    Components.AppTextField {
                                        id: portField
                                        Layout.fillWidth: true
                                        text: root.port
                                        placeholderText: "3000"
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        onTextEdited: root.port = text
                                    }
                                }

                                Components.SettingsCheckableOption {
                                    titleWidth: 136
                                    id: sslCheckbox
                                    checked: root.useSsl
                                    title: "Enable SSL"
                                    description: "Use HTTPS for the local domain when the project is ready."
                                    onToggled: function(nextChecked) {
                                        root.useSsl = nextChecked
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    title: "Notes"
                                    titleWidth: 160
                                    Components.AppTextField {
                                        id: notesField
                                        Layout.fillWidth: true
                                        text: root.notes
                                        placeholderText: "Optional notes"
                                        onTextEdited: root.notes = text
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        id: templateFormColumn
                        anchors.centerIn: parent
                        width: Math.min(560, parent.width)
                        spacing: 12

                        Components.SettingsLabeledControl {
                            title: "Local domain"
                            titleWidth: 160
                            Components.AppTextField {
                                id: templateLocalDomainField
                                Layout.fillWidth: true
                                text: root.localDomain
                                placeholderText: "my-app.engine"
                                onTextEdited: {
                                    var cleaned = root.sanitizeLocalDomain(text)
                                    if (cleaned !== text) {
                                        text = cleaned
                                    }
                                    root.localDomain = cleaned
                                    root.updateTemplateProjectFolder()
                                    root.syncFormFields()
                                }
                            }
                        }

                        Components.SettingsLabeledControl {
                            title: "Project folder"
                            titleWidth: 160
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Components.AppTextField {
                                    id: templateProjectFolderField
                                    Layout.fillWidth: true
                                    text: root.projectFolder
                                    placeholderText: "Choose a base folder first"
                                    readOnly: true
                                }

                                Components.AppButton {
                                    text: Strings.t("choose")
                                    onClicked: {
                                        root.existingProjectMode = false
                                        root.folderDialogMode = "template"
                                        folderDialog.open()
                                    }
                                }
                            }
                        }

                        Components.SettingsLabeledControl {
                            title: "Node version"
                            titleWidth: 160
                            Components.AppComboBox {
                                id: templateNodeVersionCombo
                                Layout.fillWidth: true
                                model: root.nodeVersionsForTemplate(root.selectedTemplateId)
                                currentIndex: {
                                    var versions = root.nodeVersionsForTemplate(root.selectedTemplateId)
                                    if (versions.length === 0) {
                                        return -1
                                    }
                                    var selectedIndex = find(root.nodeVersion)
                                    if (selectedIndex >= 0) {
                                        return selectedIndex
                                    }
                                    return versions.length - 1
                                }
                                onCurrentIndexChanged: {
                                    if (currentIndex >= 0 && currentIndex < (model ? model.length : 0)) {
                                        root.nodeVersion = currentText
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.nodeVersionsForTemplate(root.selectedTemplateId).length === 0
                            Layout.fillWidth: true
                            Layout.leftMargin: 168
                            text: Strings.t("no.node.runtime.installed.a.href.install.node.install.one.in.runtime.manager.a")
                            textFormat: Text.RichText
                            linkColor: Theme.accentStrong
                            color: Theme.muted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            onLinkActivated: function(_link) { root.requestNodeRuntimeInstall() }
                        }

                        Text {
                            visible: root.nodeVersionsForTemplate(root.selectedTemplateId).length > 0
                            Layout.fillWidth: true
                            Layout.leftMargin: 168
                            text: "<a href='install-more'>Install more</a>"
                            textFormat: Text.RichText
                            linkColor: Theme.accentStrong
                            color: Theme.muted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            onLinkActivated: function(_link) { root.requestNodeRuntimeInstall() }
                        }

                        Components.SettingsCheckableOption {
                            id: templateRandomPortCheckbox
                            checked: root.useRandomPort
                            title: "Pick a random port"
                            titleWidth: 136
                            description: "Let Server Engine choose the port automatically."
                            onToggled: function(nextChecked) {
                                root.useRandomPort = nextChecked
                                if (!nextChecked && root.port.trim().length === 0) {
                                    root.port = defaultPortFor(root.selectedTemplateId)
                                }
                                if (nextChecked) {
                                    root.port = root.randomPortForTemplate(root.selectedTemplateId, root.port)
                                }
                                root.syncFormFields()
                            }
                        }

                        Components.SettingsLabeledControl {
                            visible: !templateRandomPortCheckbox.checked
                            title: "Port"
                            titleWidth: 160
                            Components.AppTextField {
                                id: templatePortField
                                Layout.fillWidth: true
                                text: root.port
                                placeholderText: "3000"
                                inputMethodHints: Qt.ImhDigitsOnly
                                onTextEdited: root.port = text
                            }
                        }

                        Components.SettingsCheckableOption {
                            titleWidth: 136
                            id: templateSslCheckbox
                            checked: root.useSsl
                            title: "Enable SSL"
                            description: "Use HTTPS for the local domain when the project is ready."
                            onToggled: function(nextChecked) {
                                root.useSsl = nextChecked
                            }
                        }

                        Components.SettingsLabeledControl {
                            title: "Notes"
                            titleWidth: 160
                            Components.AppTextField {
                                id: templateNotesField
                                Layout.fillWidth: true
                                text: root.notes
                                placeholderText: "Optional notes"
                                onTextEdited: root.notes = text
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.wizardStep === 3

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(560, parent.width)
                        spacing: 14

                        Text {
                            Layout.fillWidth: true
                            text: root.createProjectStatus.length > 0
                                ? root.createProjectStatus
                                : "Creating your Node project..."
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            wrapMode: Text.WordWrap
                        }

                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: root.createProjectProgress
                            indeterminate: root.createProjectBusy && root.createProjectProgress <= 0
                        }

                        Repeater {
                            model: root.createProjectStages
                            delegate: Components.StatusProgressRow {
                                required property int index
                                required property var modelData
                                label: String(modelData || "")
                                phaseIndex: index
                                currentPhaseIndex: root.createProjectStageIndex
                                status: root.createProjectStatus
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.existingProjectValidationText.length > 0
                Layout.fillWidth: true
                text: root.existingProjectValidationText
                color: root.existingProjectValidationError ? Theme.danger : Theme.success
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Components.AppButton {
                    text: Strings.t("cancel")
                    visible: root.wizardStep !== 3 || (root.wizardStep === 3 && root.createProjectBusy && root.selectedTemplateId !== "existing")
                    enabled: root.wizardStep !== 3 ? !root.createProjectBusy : root.createProjectBusy
                    onClicked: {
                        if (root.wizardStep === 3 && root.createProjectBusy && root.selectedTemplateId !== "existing") {
                            if (dashboardBridge && dashboardBridge.cancelNodeProjectSave) {
                                dashboardBridge.cancelNodeProjectSave()
                            }
                            return
                        }
                        root.closeModal()
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Components.AppButton {
                    text: "Back"
                    visible: root.wizardStep > 0 && root.wizardStep < 3
                    onClicked: {
                        root.wizardStep = 0
                        root.existingProjectMode = false
                        root.folderDialogMode = ""
                        root.existingProjectValidationText = ""
                        root.existingProjectValidationError = false
                    }
                }

                Components.AppButton {
                    text: root.wizardStep === 3
                        ? "Close"
                        : (root.wizardStep === 0 ? "Next" : "Add Project")
                    highlighted: true
                    textColor: "white"
                    enabled: root.wizardStep === 3
                        ? !root.createProjectBusy
                        : (root.wizardStep === 0
                            ? root.selectedTemplateId.length > 0
                            : root.currentFormIsValid())
                    onClicked: {
                        if (root.wizardStep === 3) {
                            root.closeModal()
                            return
                        }
                        if (root.wizardStep === 0) {
                            if (root.selectedTemplateId === "existing") {
                                root.startExistingProjectFlow()
                                folderDialog.open()
                                return
                            }
                            if (root.selectedTemplateId.length > 0) {
                                root.applyTemplateDefaults(root.selectedTemplateId)
                                root.wizardStep = 2
                            }
                            return
                        }
                            if (root.wizardStep === 1 || root.wizardStep === 2) {
                                if (!dashboardBridge || !dashboardBridge.saveNodeProjectAsync) {
                                    root.createProjectStatus = "Project save is unavailable."
                                    return
                                }
                            var selectedRunItems = root.wizardStep === 1
                                ? root.nodeRunScriptItems
                                : root.runScriptsForTemplate(root.selectedTemplateId)
                            var selectedRun = selectedRunItems.length > 0
                                ? selectedRunItems[Math.max(0, Math.min((root.wizardStep === 1 ? nodeRunOptionsCombo.currentIndex : 0), selectedRunItems.length - 1))]
                                : ({})
                            var templateInfo = root.templateById(root.selectedTemplateId) || ({})
                            var payload = {
                                name: root.localDomain.split(".")[0],
                                local_domain: root.localDomain.trim(),
                                project_path: root.projectFolder.trim(),
                                node_version: root.nodeVersion,
                                template_id: root.selectedTemplateId,
                                template_title: String(templateInfo.title || ""),
                                runtime_type: String(templateInfo.runtimeType || ""),
                                run_script_name: String(selectedRun.name || ""),
                                run_script_command: String(selectedRun.command || ""),
                                port: root.port.trim(),
                                notes: root.notes.trim(),
                                ssl_enabled: root.useSsl,
                                ssl_enforce_tls: false,
                                ssl_allow_http: true
                            }
                            if (root.wizardStep === 2 && root.useRandomPort && payload.port.length === 0) {
                                payload.port = root.randomPortForTemplate(root.selectedTemplateId, root.port)
                            }
                            if (root.wizardStep === 2 && root.useRandomPort) {
                                payload.port = root.randomPortForTemplate(root.selectedTemplateId, root.port)
                            }
                            root.startCreateProjectFlow()
                            if (!dashboardBridge.saveNodeProjectAsync(payload)) {
                                root.finishCreateProjectFlow(false, dashboardBridge.lastOperationMessage || "Project save failed.")
                            }
                        }
                    }
                }
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: Strings.t("choose.node.project.folder")
        parentWindow: root
        onAccepted: {
            if (root.folderDialogMode === "template") {
                root.projectBasePath = root.folderPathFromUrl(selectedFolder)
                root.updateTemplateProjectFolder()
                root.syncFormFields()
                root.folderDialogMode = ""
                return
            }
            if (root.existingProjectMode || root.selectedTemplateId === "existing") {
                root.inspectExistingProjectFolder(selectedFolder)
                root.folderDialogMode = ""
                return
            }
            root.projectFolder = root.folderPathFromUrl(selectedFolder)
            root.syncFormFields()
            root.folderDialogMode = ""
        }
    }
}
