import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"
import "../website_add_site_presets.js" as SitePresets

Window {
    id: addSiteWindow

    required property var root
    readonly property var dashboardBridge: root.dashboardBridge
    property bool closeConfirmOpen: false
    property int wizardStep: 0
    property string selectedTemplateChoice: ""
    property string selectedTemplateCategory: "all"
    property bool pendingCustomAdvance: false

    property alias domainField: domainField
    property alias notesField: notesField
    property alias projectPathField: projectPathField
    property alias runningDirectoryCombo: runningDirectoryCombo
    property alias phpVersionCombo: phpVersionCombo
    property alias wordpressVersionCombo: wordpressVersionCombo
    property alias wordpressUsernameField: wordpressUsernameField
    property alias wordpressPasswordField: wordpressPasswordField
    property alias wordpressDatabasePrefixField: wordpressDatabasePrefixField
    property alias wordpressDatabaseNameField: wordpressDatabaseNameField
    property alias laravelVersionCombo: laravelVersionCombo
    property alias laravelCreateDatabaseCheckbox: laravelCreateDatabaseCheckbox
    property alias laravelDatabaseNameField: laravelDatabaseNameField
    property alias sslCheckbox: sslCheckbox
    property alias starterCheckbox: starterCheckbox

    readonly property var selectedTemplateConfig: SitePresets.templateById(selectedTemplateChoice) || SitePresets.templateById("empty")
    readonly property string selectedTemplateLabel: String(selectedTemplateConfig && selectedTemplateConfig.title ? selectedTemplateConfig.title : "")

    function debugSiteFlow(label, details) {
        console.log("[AddSite]", label, details ? JSON.stringify(details) : "")
    }

    visible: root.addSiteOpen
    width: 720
    height: 520
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("add.site")
    color: "transparent"
    modality: Qt.WindowModal
    transientParent: root && root.Window ? root.Window.window : null
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.FramelessWindowHint

    onVisibleChanged: {
        debugSiteFlow("visibleChanged", { visible: visible, addSiteOpen: root.addSiteOpen })
        if (visible) {
            wizardStep = 0
            selectedTemplateChoice = ""
            selectedTemplateCategory = "all"
            pendingCustomAdvance = false
            raise()
            requestActivate()
            Qt.callLater(function() {
                root.resetAddSiteDialog()
                root.applyDefaultPhpVersionSelection()
                root.refreshAddSiteDirectoryChoices()
                root.syncLaravelPhpCompatibility(true)
            })
            return
        }

        closeConfirmOpen = false
    }

    onClosing: function(closeEvent) {
        if (root.addSiteBusy) {
            closeEvent.accepted = false
            closeConfirmOpen = true
            return
        }
        closeEvent.accepted = true
        root.addSiteOpen = false
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        context: Qt.WindowShortcut
        onActivated: {
            if (root.addSiteBusy) {
                closeConfirmOpen = true
            } else {
                root.addSiteOpen = false
            }
        }
    }

    function requestClose() {
        if (root.addSiteBusy) {
            closeConfirmOpen = true
            return
        }
        root.addSiteOpen = false
    }

    function selectTemplateCategory(category) {
        debugSiteFlow("selectTemplateCategory", { category: category })
        selectedTemplateCategory = category
        var visibleTemplates = SitePresets.templatesForCategory(category)
        var stillVisible = false
        for (var i = 0; i < visibleTemplates.length; i++) {
            if (String(visibleTemplates[i].id || "") === String(selectedTemplateChoice || "")) {
                stillVisible = true
                break
            }
        }
        if (!stillVisible) {
            selectedTemplateChoice = ""
        }
    }

    function selectTemplateChoice(choice) {
        debugSiteFlow("selectTemplateChoice:start", { choice: choice })
        selectedTemplateChoice = choice
        root.addSiteFeedback = ""
        root.addSiteFeedbackError = false
        root.addSiteBusy = false
        root.addSiteCreationFailed = false
        root.addSiteCreationErrorMessage = ""
        root.addSiteFailedPhaseIndex = -1
        root.wordpressDownloadProgress = 0
        root.wordpressDownloadStatus = ""
        root.pendingAddSitePayload = ({})
        pendingCustomAdvance = false
        if (domainField) {
            domainField.text = ""
        }
        if (projectPathField) {
            projectPathField.text = ""
        }
        var template = SitePresets.templateById(choice) || SitePresets.templateById("empty")
        var mode = String(template && template.mode ? template.mode : "basic")
        root.addSiteProjectBasePath = dashboardBridge.settingsDefaultProjectFolder || "~/ServerEngine"
        if (mode === "wordpress") {
            root.addSiteTemplateIndex = 1
            root.laravelCompatibilityMessage = ""
            root.laravelCompatibilityError = false
            root.updateWordPressProjectPath()
            root.applyDefaultPhpVersionSelection()
            root.refreshAddSiteDirectoryChoices()
            debugSiteFlow("selectTemplateChoice:wordpress", {
                templateIndex: root.addSiteTemplateIndex,
                projectPath: projectPathField ? projectPathField.text : "",
                basePath: root.addSiteProjectBasePath
            })
            return
        }
        if (mode === "laravel") {
            root.addSiteTemplateIndex = 2
            root.updateWordPressProjectPath()
            root.refreshAddSiteDirectoryChoices()
            root.syncLaravelPhpCompatibility(true)
            debugSiteFlow("selectTemplateChoice:laravel", {
                templateIndex: root.addSiteTemplateIndex,
                projectPath: projectPathField ? projectPathField.text : "",
                basePath: root.addSiteProjectBasePath
            })
            return
        }
        if (mode === "composer") {
            root.addSiteTemplateIndex = 0
            root.updateWordPressProjectPath()
            root.refreshAddSiteDirectoryChoices()
            debugSiteFlow("selectTemplateChoice:composer", {
                templateIndex: root.addSiteTemplateIndex,
                projectPath: projectPathField ? projectPathField.text : "",
                basePath: root.addSiteProjectBasePath
            })
            return
        }
        root.addSiteTemplateIndex = 0
        root.laravelCompatibilityMessage = ""
        root.laravelCompatibilityError = false
        starterCheckbox.checked = choice === "empty" && Boolean(template && template.createStarter)
        if (choice === "empty") {
            root.updateWordPressProjectPath()
            root.refreshAddSiteDirectoryChoices()
        }
        debugSiteFlow("selectTemplateChoice:basic", {
            templateIndex: root.addSiteTemplateIndex,
            starterChecked: starterCheckbox.checked,
            projectPath: projectPathField ? projectPathField.text : ""
        })
    }

    function startCreateSiteFlow() {
        debugSiteFlow("startCreateSiteFlow:begin", {
            wizardStep: wizardStep,
            templateChoice: selectedTemplateChoice,
            templateIndex: root.addSiteTemplateIndex,
            projectPath: projectPathField ? projectPathField.text : "",
            domain: domainField ? domainField.text : "",
            busy: root.addSiteBusy
        })
        if (root.addSiteBusy) {
            debugSiteFlow("startCreateSiteFlow:blocked-busy")
            return
        }
        root.addSiteFeedback = ""
        root.addSiteFeedbackError = false
        root.addSiteCreationFailed = false
        root.addSiteCreationErrorMessage = ""
        root.addSiteFailedPhaseIndex = -1
        var templateConfig = selectedTemplateConfig || SitePresets.templateById(selectedTemplateChoice) || ({})
        var templateMode = String(templateConfig.mode || "")
        debugSiteFlow("startCreateSiteFlow:template", {
            mode: templateMode,
            frameworkPreset: templateConfig.frameworkPreset || "",
            webRoot: templateConfig.webRoot || "",
            createDatabase: Boolean(templateConfig.createDatabase)
        })
        if (!root.canAddPhpSite) {
            root.addSiteFeedback = Strings.t("start.apache.or.nginx.before.adding.a.php.site")
            root.addSiteFeedbackError = true
            debugSiteFlow("startCreateSiteFlow:no-web-server")
            return
        }
            if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2 || templateMode === "composer") {
            root.updateWordPressProjectPath()
        }
        var payload = root.addSitePayload()
        debugSiteFlow("startCreateSiteFlow:payload", {
            local_domain: payload.local_domain,
            project_path: payload.project_path,
            framework_preset: payload.framework_preset,
            web_root: payload.web_root,
            database_enabled: payload.database_enabled,
            database_name: payload.database_name
        })
        if (!root.isValidLocalDomain(String(payload.local_domain || ""))) {
            root.addSiteFeedback = Strings.t("domain.may.only.use.lowercase.letters.numbers.hyphens.and.dots.for.example.example.test")
            root.addSiteFeedbackError = true
            debugSiteFlow("startCreateSiteFlow:invalid-domain", { local_domain: payload.local_domain })
            return
        }
        if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2 || templateMode === "composer") {
            if (root.addSiteTemplateIndex === 1 || Boolean(payload.database_enabled)) {
                var databaseCheckMessage = dashboardBridge.validateNewDatabaseName(String(payload.database_name || ""))
                if (databaseCheckMessage.length > 0) {
                    root.addSiteFeedback = databaseCheckMessage
                    root.addSiteFeedbackError = true
                    debugSiteFlow("startCreateSiteFlow:invalid-database", { database_name: payload.database_name, message: databaseCheckMessage })
                    return
                }
            }
            if (dashboardBridge.pathExists(String(payload.project_path || ""))
                    && !dashboardBridge.pathIsEmpty(String(payload.project_path || ""))) {
                root.projectPathError = true
                root.projectPathErrorMessage = "Choose a new or empty folder for this preset. Choose Custom Site for an existing project."
                debugSiteFlow("startCreateSiteFlow:path-exists", { project_path: payload.project_path })
                return
            }
            root.pendingAddSitePayload = payload
            root.addSiteBusy = true
            wizardStep = 2
            root.wordpressDownloadProgress = 1
            root.wordpressDownloadStatus = templateMode === "composer"
                ? "Starting composer setup..."
                : (root.addSiteTemplateIndex === 2
                    ? Strings.t("starting.laravel.setup")
                    : Strings.t("starting.wordpress.setup"))
            debugSiteFlow("startCreateSiteFlow:async-start", {
                wizardStep: wizardStep,
                status: root.wordpressDownloadStatus,
                payload: root.pendingAddSitePayload
            })
            if (!dashboardBridge.createSiteAsync(root.pendingAddSitePayload)) {
                root.addSiteBusy = false
                root.addSiteFeedback = dashboardBridge.lastOperationMessage.length > 0
                    ? dashboardBridge.lastOperationMessage
                    : Strings.t("create.site.failed")
                root.addSiteFeedbackError = true
                debugSiteFlow("startCreateSiteFlow:createSiteAsync-failed", {
                    message: dashboardBridge.lastOperationMessage,
                    error: dashboardBridge.lastOperationError
                })
            }
            return
            }
            if (dashboardBridge.pathExists(String(payload.project_path || ""))
                    && selectedTemplateChoice === "empty"
                    && !dashboardBridge.pathIsEmpty(String(payload.project_path || ""))) {
                root.projectPathError = true
                root.projectPathErrorMessage = "Empty sites can only be created in a new or empty folder. Choose Custom Site for an existing project."
                return
            }
            root.pendingAddSitePayload = payload
            root.addSiteBusy = true
            wizardStep = 2
            root.wordpressDownloadProgress = 1
            root.wordpressDownloadStatus = "Creating site..."
            debugSiteFlow("startCreateSiteFlow:async-start", { wizardStep: wizardStep })
            if (!dashboardBridge.createSiteAsync(root.pendingAddSitePayload)) {
                root.addSiteBusy = false
                root.addSiteFeedback = dashboardBridge.lastOperationMessage.length > 0
                    ? dashboardBridge.lastOperationMessage
                    : Strings.t("create.site.failed")
                root.addSiteFeedbackError = true
                debugSiteFlow("startCreateSiteFlow:sync-failed", {
                message: dashboardBridge.lastOperationMessage,
                error: dashboardBridge.lastOperationError
            })
        }
    }

    Rectangle {
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
                addSiteWindow.startSystemMove()
                mouse.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: wizardStep === 0
                    ? Strings.t("select.template")
                    : (wizardStep === 1
                        ? "Choose options for your new site:"
                        : "Creating site...")
                visible: wizardStep !== 2
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: wizardStep

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: -20
                        anchors.rightMargin: -20
                        height: 1
                        color: Theme.border
                    }

                    RowLayout {
                        id: categoryRow
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 12
                        spacing: 8

                        Repeater {
                            model: SitePresets.templateCategories()

                            delegate: Components.AppButton {
                                required property var modelData
                                text: modelData.title
                                highlighted: selectedTemplateCategory === modelData.id
                                textColor: selectedTemplateCategory === modelData.id ? "white" : Theme.text
                                onClicked: selectTemplateCategory(modelData.id)
                            }
                        }
                    }

                    GridLayout {
                        id: templateGrid
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 56
                        width: parent.width
                        columns: 5
                        columnSpacing: 14
                        rowSpacing: 0
                        property int cellWidth: Math.floor((width - (columnSpacing * 4)) / 5)
                        height: implicitHeight + 14

                        Repeater {
                            model: SitePresets.templatesForCategory(selectedTemplateCategory)

                            delegate: Item {
                                required property var modelData
                                Layout.preferredWidth: templateGrid.cellWidth
                                Layout.minimumWidth: templateGrid.cellWidth
                                Layout.maximumWidth: templateGrid.cellWidth
                                Layout.preferredHeight: 106
                                Layout.minimumHeight: 106
                                Layout.maximumHeight: 106

                                readonly property bool selected: selectedTemplateChoice === modelData.id

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
                                                source: Qt.resolvedUrl("../" + String(modelData.icon || ""))
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
                                    onClicked: selectTemplateChoice(modelData.id)
                                }
                            }
                        }

                        Item {
                            Layout.preferredWidth: templateGrid.cellWidth
                            Layout.minimumWidth: templateGrid.cellWidth
                            Layout.maximumWidth: templateGrid.cellWidth
                            Layout.preferredHeight: 106
                            Layout.minimumHeight: 106
                            Layout.maximumHeight: 106
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

                    Components.AppScrollArea {
                        anchors.fill: parent
                        viewportMargins: 0
                        clipContent: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 16

                            Text {
                                Layout.fillWidth: true
                                text: selectedTemplateLabel.length > 0
                                    ? "Template: " + selectedTemplateLabel
                                    : "Template: Empty"
                                color: Theme.muted
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            Components.SettingsLabeledInput {
                                title: Strings.t("domain")
                                Components.AppTextField {
                                    id: domainField
                                    Layout.fillWidth: true
                                    placeholderText: Strings.t("example.engine")
                                    text: ""
                                    enabled: !root.addSiteBusy
                                    inputMethodHints: Qt.ImhLowercaseOnly | Qt.ImhNoPredictiveText
                                    validator: RegularExpressionValidator {
                                        regularExpression: /^[a-z0-9.-]*$/
                                    }
                                    onTextEdited: {
                                        var cleaned = root.sanitizeLocalDomain(text)
                                        if (cleaned !== text) {
                                            text = cleaned
                                        }
                                        if (root.addSiteFeedbackError && root.addSiteFeedback.indexOf("Domain") === 0) {
                                            root.addSiteFeedback = ""
                                            root.addSiteFeedbackError = false
                                        }
                                        if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2
                                            || (selectedTemplateConfig && selectedTemplateConfig.mode === "composer")
                                            || selectedTemplateChoice === "empty") {
                                            root.updateWordPressProjectPath()
                                        }
                                        debugSiteFlow("domainEdited", {
                                            value: text,
                                            projectPath: projectPathField ? projectPathField.text : "",
                                            templateChoice: selectedTemplateChoice
                                        })
                                    }
                                    onTextChanged: {
                                        if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2
                                            || (selectedTemplateConfig && selectedTemplateConfig.mode === "composer")
                                            || selectedTemplateChoice === "empty") {
                                            root.updateWordPressProjectPath()
                                        }
                                        debugSiteFlow("domainChanged", {
                                            value: text,
                                            projectPath: projectPathField ? projectPathField.text : "",
                                            templateChoice: selectedTemplateChoice
                                        })
                                    }
                                }
                            }

                            Components.SettingsLabeledInput {
                                title: Strings.t("notes")
                                Components.AppTextField {
                                    id: notesField
                                    Layout.fillWidth: true
                                    placeholderText: Strings.t("short.description")
                                    enabled: !root.addSiteBusy
                                }
                            }

                            Components.SettingsLabeledInput {
                                title: Strings.t("project.folder")
                                description: root.projectPathError ? root.projectPathErrorMessage : ""
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Components.AppTextField {
                                        id: projectPathField
                                        Layout.fillWidth: true
                                        placeholderText: Strings.t("users.you.sites.example")
                                        enabled: !root.addSiteBusy
                                        readOnly: true
                                        onTextChanged: {
                                            root.refreshAddSiteDirectoryChoices()
                                            debugSiteFlow("projectPathChanged", {
                                                value: text,
                                                templateChoice: selectedTemplateChoice
                                            })
                                        }
                                    }
                                    Components.AppButton {
                                        text: Strings.t("choose")
                                        enabled: !root.addSiteBusy
                                        onClicked: {
                                            root.addSiteFeedback = ""
                                            root.addSiteFeedbackError = false
                                            debugSiteFlow("chooseProjectFolder:open")
                                            folderDialog.open()
                                        }
                                    }
                                }
                            }

    Components.SettingsLabeledControl {
                                visible: selectedTemplateChoice === "custom"
                                title: Strings.t("running.directory")
                                Components.AppComboBox {
                                    id: runningDirectoryCombo
                                    Layout.fillWidth: true
                                    model: root.addSiteDirectoryChoices
                                    currentIndex: 0
                                    enabled: !root.addSiteBusy
                                }
                            }

                            Components.SettingsLabeledControl {
                                title: Strings.t("php")
                                description: root.addSiteTemplateIndex === 2 && root.laravelCompatibilityMessage.length > 0
                                    ? root.laravelCompatibilityMessage
                                    : (selectedTemplateConfig && selectedTemplateConfig.frameworkPreset === "cakephp"
                                        ? "CakePHP requires PHP intl extension."
                                        : "")
                                Components.AppComboBox {
                                    id: phpVersionCombo
                                    Layout.fillWidth: true
                                    model: dashboardBridge.phpVersions
                                    enabled: !root.addSiteBusy
                                    onCurrentTextChanged: root.syncLaravelPhpCompatibility(false)
                                }
                            }

                            Components.SettingsLabeledControl {
                                visible: root.addSiteTemplateIndex === 1
                                title: Strings.t("wordpress.version")
                                Components.AppComboBox {
                                    id: wordpressVersionCombo
                                    Layout.fillWidth: true
                                    model: dashboardBridge.wordpressVersions
                                    enabled: !root.addSiteBusy
                                }
                            }

                            Components.SettingsLabeledInput {
                                visible: root.addSiteTemplateIndex === 1
                                title: Strings.t("wordpress.username")
                                Components.AppTextField {
                                    id: wordpressUsernameField
                                    Layout.fillWidth: true
                                    text: Strings.t("admin")
                                    placeholderText: Strings.t("admin")
                                    enabled: !root.addSiteBusy
                                }
                            }

                            Components.SettingsLabeledInput {
                                visible: root.addSiteTemplateIndex === 1
                                title: Strings.t("wordpress.password")
                                Components.AppTextField {
                                    id: wordpressPasswordField
                                    Layout.fillWidth: true
                                    echoMode: TextInput.Password
                                    placeholderText: Strings.t("password")
                                    enabled: !root.addSiteBusy
                                }
                            }

                            Components.SettingsLabeledInput {
                                visible: root.addSiteTemplateIndex === 1
                                title: Strings.t("database.prefix")
                                Components.AppTextField {
                                    id: wordpressDatabasePrefixField
                                    Layout.fillWidth: true
                                    text: "wp_"
                                    enabled: !root.addSiteBusy
                                }
                            }

                            Components.SettingsLabeledInput {
                                visible: root.addSiteTemplateIndex === 1
                                title: Strings.t("database.name")
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Components.AppTextField {
                                        id: wordpressDatabaseNameField
                                        Layout.fillWidth: true
                                        text: root.randomWordPressDatabaseName()
                                        enabled: !root.addSiteBusy
                                        validator: RegularExpressionValidator {
                                            regularExpression: /^[A-Za-z_][A-Za-z0-9_]*$/
                                        }
                                        onTextEdited: {
                                            var cleanedValue = String(text || "").replace(/[^A-Za-z0-9_]/g, "")
                                            if (cleanedValue !== text) {
                                                text = cleanedValue
                                            }
                                        }
                                        onPressed: {
                                            if (!root.addSiteBusy) {
                                                text = root.randomWordPressDatabaseName()
                                                root.addSiteFeedback = ""
                                                root.addSiteFeedbackError = false
                                            }
                                        }
                                    }
                                    Components.AppButton {
                                        text: Strings.t("change")
                                        enabled: !root.addSiteBusy
                                        onClicked: {
                                            wordpressDatabaseNameField.text = root.randomWordPressDatabaseName()
                                            root.addSiteFeedback = ""
                                            root.addSiteFeedbackError = false
                                        }
                                    }
                                }
                            }

                            Components.SettingsLabeledControl {
                                visible: root.addSiteTemplateIndex === 2
                                title: Strings.t("laravel.version")
                                Components.AppComboBox {
                                    id: laravelVersionCombo
                                    Layout.fillWidth: true
                                    model: dashboardBridge.laravelVersions
                                    enabled: !root.addSiteBusy
                                    onCurrentTextChanged: root.syncLaravelPhpCompatibility(true)
                                }
                            }

                            Components.SettingsCheckableOption {
                                visible: root.addSiteTemplateIndex === 2
                                id: laravelCreateDatabaseCheckbox
                                title: Strings.t("create.database")
                                description: "Create a database for the Laravel site automatically."
                                checked: false
                                itemEnabled: !root.addSiteBusy
                                onToggled: function(nextChecked) {
                                    root.addSiteFeedback = ""
                                    root.addSiteFeedbackError = false
                                }
                            }

                            Components.SettingsLabeledInput {
                                visible: root.addSiteTemplateIndex === 2 && laravelCreateDatabaseCheckbox.checked
                                title: Strings.t("database.name")
                                Components.AppTextField {
                                    id: laravelDatabaseNameField
                                    Layout.fillWidth: true
                                    text: root.databaseNameFromDomain(domainField.text.trim())
                                    enabled: !root.addSiteBusy
                                    validator: RegularExpressionValidator {
                                        regularExpression: /^[A-Za-z_][A-Za-z0-9_]*$/
                                    }
                                    onTextEdited: {
                                        var cleanedValue = String(text || "").replace(/[^A-Za-z0-9_]/g, "")
                                        if (cleanedValue !== text) {
                                            text = cleanedValue
                                        }
                                    }
                                }
                            }

                            Components.SettingsCheckableOption {
                                visible: selectedTemplateChoice === "empty"
                                id: starterCheckbox
                                title: Strings.t("create.starter.html")
                                description: "Create a simple starter index.html in the site folder."
                                checked: false
                                itemEnabled: !root.addSiteBusy && selectedTemplateChoice === "empty"
                            }

                            Components.SettingsCheckableOption {
                                id: sslCheckbox
                                title: Strings.t("enable.ssl")
                                description: "Create a local HTTPS certificate for this site."
                                checked: false
                                itemEnabled: !root.addSiteBusy
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(560, parent.width)
                        spacing: 14

                        Text {
                            Layout.fillWidth: true
                            text: root.addSiteBusy
                                ? root.wordpressDownloadStatus
                                : (root.addSiteCreationFailed
                                    ? "Site creation failed. View logs for more info."
                                    : (root.addSiteCreationSucceeded
                                        ? "Congratulations! Site created successfully."
                                        : "Ready to create site."))
                            color: root.addSiteCreationFailed
                                ? Theme.danger
                                : (root.addSiteCreationSucceeded ? Theme.success : Theme.text)
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            wrapMode: Text.WordWrap
                        }

                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: Math.max(0, root.wordpressDownloadProgress)
                            indeterminate: root.addSiteBusy && root.wordpressDownloadProgress <= 0
                            visible: wizardStep === 2
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: wizardStep === 2 && root.addSiteBusy && root.wordpressDownloadProgress >= 0
                            text: root.wordpressDownloadProgress + "% complete"
                            color: Theme.muted
                            font.pixelSize: 13
                        }

                        ColumnLayout {
                            visible: wizardStep === 2
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: selectedTemplateConfig && selectedTemplateConfig.mode === "composer"
                                    ? root.composerSetupStages
                                    : (root.addSiteTemplateIndex === 2
                                        ? root.laravelSetupStages
                                        : (selectedTemplateChoice === "empty" || selectedTemplateChoice === "custom"
                                            ? root.basicSetupStages
                                            : root.wordpressSetupStages))
                                delegate: Components.StatusProgressRow {
                                    required property int index
                                    required property var modelData
                                    readonly property var stages: selectedTemplateConfig && selectedTemplateConfig.mode === "composer"
                                        ? root.composerSetupStages
                                        : (root.addSiteTemplateIndex === 2
                                            ? root.laravelSetupStages
                                            : (selectedTemplateChoice === "empty" || selectedTemplateChoice === "custom"
                                                ? root.basicSetupStages
                                                : root.wordpressSetupStages))
                                    Layout.fillWidth: true
                                    label: String(modelData || "")
                                    phaseIndex: index
                                    currentPhaseIndex: root.addSiteCreationFailed
                                        ? root.addSiteFailedPhaseIndex
                                        : (root.addSiteCreationSucceeded
                                            ? stages.length
                                            : stages.indexOf(String(root.wordpressDownloadStatus || "")))
                                    status: root.wordpressDownloadStatus
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Components.AppButton {
                    visible: !(wizardStep === 2 && !root.addSiteBusy)
                    text: Strings.t("cancel")
                    enabled: true
                    onClicked: addSiteWindow.requestClose()
                }

                Item {
                    Layout.fillWidth: true
                }

                Components.AppButton {
                    visible: wizardStep === 1
                    text: "Previous"
                    enabled: !root.addSiteBusy
                    onClicked: wizardStep = 0
                }

                Components.AppButton {
                    text: wizardStep === 0
                        ? "Next"
                        : (wizardStep === 1
                            ? Strings.t("create.site")
                            : (root.addSiteBusy ? "Creating..." : "Close"))
                    highlighted: true
                    textColor: "white"
                    enabled: wizardStep === 0
                        ? selectedTemplateChoice.length > 0
                        : (wizardStep === 1
                            ? root.isValidLocalDomain(domainField.text.trim())
                                && projectPathField.text.trim().length > 0
                                && !root.projectPathError
                                && (root.addSiteTemplateIndex !== 1
                                    || (wordpressVersionCombo.currentIndex >= 0
                                        && wordpressUsernameField.text.trim().length > 0
                                        && wordpressPasswordField.text.length > 0
                                        && wordpressDatabasePrefixField.text.trim().length > 0
                                        && wordpressDatabaseNameField.text.trim().length > 0))
                                && (root.addSiteTemplateIndex !== 2
                            || (!laravelCreateDatabaseCheckbox.checked
                                        || laravelDatabaseNameField.text.trim().length > 0))
                                && (root.addSiteTemplateIndex !== 2 || !root.laravelCompatibilityError)
                            : !root.addSiteBusy)
                    onClicked: {
                        if (wizardStep === 0) {
                            debugSiteFlow("footerNext:step0", { selectedTemplateChoice: selectedTemplateChoice })
                            if (selectedTemplateChoice.length === 0) {
                                return
                            }
                            if (selectedTemplateChoice === "custom" || selectedTemplateChoice === "empty") {
                                pendingCustomAdvance = true
                                folderDialog.open()
                                return
                            }
                            selectTemplateChoice(selectedTemplateChoice)
                            wizardStep = 1
                            debugSiteFlow("footerNext:step0->1", { wizardStep: wizardStep, selectedTemplateChoice: selectedTemplateChoice })
                            return
                        }
                        if (wizardStep === 1) {
                            debugSiteFlow("footerCreate:step1")
                            startCreateSiteFlow()
                            return
                        }
                        if (!root.addSiteBusy) {
                            debugSiteFlow("footerClose:step2")
                            root.resetAddSiteDialog()
                            root.addSiteOpen = false
                        }
                    }
                }
            }
        }
    }

    Components.AppDialogWindow {
        id: closeConfirmWindow
        visible: addSiteWindow.closeConfirmOpen
        width: 440
        height: 200
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: Strings.t("cancel.site.creation")
        heading: Strings.t("cancel.site.creation")
        subtitle: selectedTemplateConfig && selectedTemplateConfig.mode === "composer"
            ? "Composer setup is still running."
            : (root.addSiteTemplateIndex === 2
                ? Strings.t("laravel.setup.is.still.running")
                : Strings.t("wordpress.setup.is.still.running"))
        confirmText: Strings.t("cancel.job")
        cancelText: Strings.t("keep.working")
        footerDividerVisible: false
        bodyScrollable: false
        transientParent: root && root.Window ? root.Window.window : null

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: Strings.t("canceling.will.stop.the.setup.job.and.close.the.add.site.dialog")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: Strings.t("partial.files.or.a.partially.created.database.may.remain.and.can.be.cleaned.up.manually")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }

        onCancelRequested: {
            addSiteWindow.closeConfirmOpen = false
        }

        onConfirmRequested: {
            dashboardBridge.cancelSiteCreation()
            root.resetAddSiteDialog()
            root.addSiteFeedback = Strings.t("site.creation.cancelled")
            root.addSiteFeedbackError = false
            root.addSiteOpen = false
            addSiteWindow.closeConfirmOpen = false
        }

        onVisibleChanged: {
            if (!visible) {
                addSiteWindow.closeConfirmOpen = false
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: Strings.t("choose.project.folder")
        parentWindow: addSiteWindow
        onAccepted: {
            var selectedPath = root.folderPathFromUrl(selectedFolder)
            if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2) {
                root.addSiteProjectBasePath = selectedPath
                root.updateWordPressProjectPath()
            } else if (selectedTemplateChoice === "custom" || selectedTemplateChoice === "empty") {
                projectPathField.text = selectedPath
                root.refreshAddSiteDirectoryChoices()
                if (pendingCustomAdvance) {
                    pendingCustomAdvance = false
                    selectTemplateChoice(selectedTemplateChoice)
                    projectPathField.text = selectedPath
                    wizardStep = 1
                }
            } else {
                projectPathField.text = selectedPath
                root.refreshAddSiteDirectoryChoices()
            }
        }
    }
}
