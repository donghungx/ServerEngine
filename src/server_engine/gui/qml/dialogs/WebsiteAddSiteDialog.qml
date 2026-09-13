import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components" as Components
import "../theme"
import "../i18n"

Item {
    id: host
    required property var root
    readonly property var dashboardBridge: root.dashboardBridge
    property bool closeConfirmOpen: false

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

    Components.AppDialogWindow {
        id: addSiteWindow
        property int dialogHeight: root.addSiteBusy
            ? 360
            : (root.addSiteTemplateIndex === 1
                ? 576
                : (root.addSiteTemplateIndex === 2
                    ? (laravelCreateDatabaseCheckbox.checked ? 560 : 492)
                    : 480))
        width: 640
        height: dialogHeight
        minimumWidth: width
        maximumWidth: width

        minimumHeight: 360
        maximumHeight: 720
        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        visible: root.addSiteOpen
        title: Strings.t("add.site")
        heading: Strings.t("create.local.site")
        confirmText: Strings.t("create.site")
        cancelText: Strings.t("cancel")
        footerDividerVisible: false
        bodyScrollable: false
        feedbackText: root.addSiteFeedback
        feedbackIsError: root.addSiteFeedbackError || dashboardBridge.lastOperationError
        confirmEnabled: root.isValidLocalDomain(domainField.text.trim())
            && projectPathField.text.trim().length > 0
            && !root.addSiteBusy
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
        confirmButtonEnabled: !root.addSiteBusy
        cancelButtonEnabled: !root.addSiteBusy
        footerVisible: !root.addSiteBusy
        transientParent: root.Window.window
        closeConfirmationEnabled: root.addSiteBusy && (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2)
        onCloseRequested: {
            closeConfirmOpen = true
        }

        onVisibleChanged: {
            if (visible) {
                Qt.callLater(function() {
                    root.resetAddSiteDialog()
                    root.applyDefaultPhpVersionSelection()
                    root.refreshAddSiteDirectoryChoices()
                    root.syncLaravelPhpCompatibility(true)
                })
            }
        }

        onCancelRequested: {
            if (root.addSiteBusy) {
                return
            }
            root.addSiteFeedback = ""
            root.addSiteFeedbackError = false
            root.addSiteOpen = false
        }

        onConfirmRequested: {
            if (root.addSiteBusy) {
                return
            }
            root.addSiteFeedback = ""
            root.addSiteFeedbackError = false
            if (!root.canAddPhpSite) {
                root.addSiteFeedback = Strings.t("start.apache.or.nginx.before.adding.a.php.site")
                root.addSiteFeedbackError = true
                return
            }
            if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2) {
                root.updateWordPressProjectPath()
            }
            var payload = root.addSitePayload()
            if (!root.isValidLocalDomain(String(payload.local_domain || ""))) {
                root.addSiteFeedback = Strings.t("domain.may.only.use.lowercase.letters.numbers.hyphens.and.dots.for.example.example.test")
                root.addSiteFeedbackError = true
                return
            }
            if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2) {
                if (root.addSiteTemplateIndex === 1 || Boolean(payload.database_enabled)) {
                    var databaseCheckMessage = dashboardBridge.validateNewDatabaseName(String(payload.database_name || ""))
                    if (databaseCheckMessage.length > 0) {
                        root.addSiteFeedback = databaseCheckMessage
                        root.addSiteFeedbackError = true
                        return
                    }
                }
                if (dashboardBridge.pathExists(String(payload.project_path || ""))) {
                    root.addSiteFeedback = Strings.t("project.folder.already.exists.choose.a.different.domain.or.base.folder")
                    root.addSiteFeedbackError = true
                    return
                }
                root.pendingAddSitePayload = payload
                root.addSiteBusy = true
                root.wordpressDownloadProgress = 1
                root.wordpressDownloadStatus = root.addSiteTemplateIndex === 2
                    ? Strings.t("starting.laravel.setup")
                    : Strings.t("starting.wordpress.setup")
                if (!dashboardBridge.createSiteAsync(root.pendingAddSitePayload)) {
                    root.addSiteBusy = false
                    root.addSiteFeedback = dashboardBridge.lastOperationMessage.length > 0
                        ? dashboardBridge.lastOperationMessage
                        : Strings.t("create.site.failed")
                    root.addSiteFeedbackError = true
                }
                return
            }
            root.addSiteBusy = true
            root.finishAddSiteWithPayload(payload)
        }

        Components.SettingsLabeledControl {
            Layout.fillWidth: true
            visible: !(root.addSiteBusy && (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2))
            title: Strings.t("site.template")
            description: "Choose how the local site should be created."

            Components.AppComboBox {
                id: siteTemplateCombo
                Layout.fillWidth: true
                model: [
                    Strings.t("custom.site"),
                    Strings.t("wordpress"),
                    Strings.t("laravel")
                ]
                currentIndex: root.addSiteTemplateIndex
                enabled: !root.addSiteBusy
                onCurrentIndexChanged: {
                    if (currentIndex === root.addSiteTemplateIndex) {
                        return
                    }
                    root.addSiteTemplateIndex = currentIndex
                    root.addSiteFeedback = ""
                    root.addSiteFeedbackError = false
                    if (currentIndex === 1 || currentIndex === 2) {
                        root.addSiteProjectBasePath = dashboardBridge.settingsDefaultProjectFolder || "~/ServerEngine"
                        root.updateWordPressProjectPath()
                    }
                    if (currentIndex === 2) {
                        laravelCreateDatabaseCheckbox.checked = false
                        root.syncLaravelPhpCompatibility(true)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.addSiteBusy && (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2)
            spacing: 16

            Label {
                Layout.fillWidth: true
                text: root.wordpressDownloadStatus
                color: Theme.text
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            ProgressBar {
                Layout.fillWidth: true
                indeterminate: root.wordpressDownloadProgress < 0
                from: 0
                to: 100
                value: Math.max(0, root.wordpressDownloadProgress)
            }

            Label {
                Layout.fillWidth: true
                visible: root.wordpressDownloadProgress >= 0
                text: root.wordpressDownloadProgress + "% complete"
                color: Theme.muted
                font.pixelSize: 13
            }

            Repeater {
                model: (root.addSiteTemplateIndex === 2 ? root.laravelSetupStages : root.wordpressSetupStages).length
                delegate: Components.StatusProgressRow {
                    required property int index
                    Layout.fillWidth: true
                    readonly property var stages: root.addSiteTemplateIndex === 2 ? root.laravelSetupStages : root.wordpressSetupStages
                    readonly property string stageText: String(stages[index] || "")
                    label: stageText
                    phaseIndex: index
                    currentPhaseIndex: stages.indexOf(String(root.wordpressDownloadStatus || ""))
                    status: root.wordpressDownloadStatus
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.addSiteBusy
            spacing: 16

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
                        if (root.addSiteTemplateIndex === 1 || root.addSiteTemplateIndex === 2) {
                            root.updateWordPressProjectPath()
                        }
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

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Components.AppTextField {
                        id: projectPathField
                        Layout.fillWidth: true
                        placeholderText: Strings.t("users.you.sites.example")
                        enabled: !root.addSiteBusy
                        readOnly: true
                        onTextChanged: root.refreshAddSiteDirectoryChoices()
                    }

                    Components.AppButton {
                        text: Strings.t("choose")
                        enabled: !root.addSiteBusy
                        onClicked: {
                            root.addSiteFeedback = ""
                            root.addSiteFeedbackError = false
                            folderDialog.open()
                        }
                    }
                }
            }

            Components.SettingsLabeledControl {
                visible: root.addSiteTemplateIndex === 0
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
                    : ""

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
                id: laravelCreateDatabaseCheckbox
                visible: root.addSiteTemplateIndex === 2
                title: Strings.t("create.database")
                description: "Create a database for the Laravel site automatically."
                checked: true
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
                id: sslCheckbox
                title: Strings.t("enable.ssl")
                description: "Create a local HTTPS certificate for this site."
                checked: false
                itemEnabled: !root.addSiteBusy
            }

            Components.SettingsCheckableOption {
                id: starterCheckbox
                visible: root.addSiteTemplateIndex === 0
                title: Strings.t("create.starter.html")
                description: "Create a simple starter index.html in the site folder."
                checked: false
                itemEnabled: !root.addSiteBusy && root.addSiteTemplateIndex === 0
            }
        }
    }

    Components.AppDialogWindow {
        id: closeConfirmWindow
        visible: host.closeConfirmOpen
        width: 440
        height: 200
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: Strings.t("cancel.site.creation")
        heading: Strings.t("cancel.site.creation")
        subtitle: root.addSiteTemplateIndex === 2
            ? Strings.t("laravel.setup.is.still.running")
            : Strings.t("wordpress.setup.is.still.running")
        confirmText: Strings.t("cancel.job")
        cancelText: Strings.t("keep.working")
        footerDividerVisible: false
        bodyScrollable: false
        transientParent: root.Window.window

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
            host.closeConfirmOpen = false
        }

        onConfirmRequested: {
            dashboardBridge.cancelSiteCreation()
            root.resetAddSiteDialog()
            root.addSiteFeedback = Strings.t("site.creation.cancelled")
            root.addSiteFeedbackError = false
            root.addSiteOpen = false
            host.closeConfirmOpen = false
        }

        onVisibleChanged: {
            if (!visible) {
                host.closeConfirmOpen = false
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
            } else {
                projectPathField.text = selectedPath
                root.refreshAddSiteDirectoryChoices()
            }
        }
    }
}
