import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: host
    required property var root
    readonly property var bridge: root ? root.dashboardBridge : null

    function resetDialog() {
        addNodeProjectWindow.clearForm()
    }

    Window {
        id: addNodeProjectWindow
        width: 800
        height: 480
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        visible: root.addNodeProjectOpen
        title: "Add Node Project"
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
        modality: Qt.ApplicationModal
        color: Theme.surface

        property bool nodeProjectSaveBusy: bridge ? bridge.nodeProjectSaveBusy : false
        property bool closeOnNodeSaveSuccess: false
        property string nodeRunCommandText: ""
        property string nodePathValidationText: ""
        property bool nodePathValidationError: false
        property bool nodePathValid: false
        property string nodeDomainValidationText: ""
        property bool nodeDomainValidationError: false
        property var nodeRunScriptItems: []

        property alias nodeDomainField: nodeDomainField
        property alias nodeProjectPathField: nodeProjectPathField
        property alias nodeDetectedPortField: nodeDetectedPortField
        property alias nodeNotesField: nodeNotesField
        property alias nodeSslCheckbox: nodeSslCheckbox
        property alias nodeVersionCombo: nodeVersionCombo
        property alias nodeRunOptionsCombo: nodeRunOptionsCombo

        readonly property bool confirmEnabled: nodeDomainField.text.trim().length > 0
            && nodeProjectPathField.text.trim().length > 0
            && !root.nodeDomainExists(nodeDomainField.text)
            && nodeVersionCombo.currentIndex >= 0
            && nodeRunOptionsCombo.currentIndex >= 0
            && nodePathValid
            && !nodeProjectSaveBusy

        readonly property string footerStatusText: {
            if (root.addNodeProjectFeedback.length > 0) {
                return root.addNodeProjectFeedback
            }
            if (nodePathValidationError && nodePathValidationText.length > 0) {
                return nodePathValidationText
            }
            if (nodeDomainValidationError && nodeDomainValidationText.length > 0) {
                return nodeDomainValidationText
            }
            return ""
        }

        readonly property bool footerStatusError: {
            if (root.addNodeProjectFeedback.length > 0) {
                return root.addNodeProjectFeedbackError
            }
            return nodePathValidationError || nodeDomainValidationError
        }

        onVisibleChanged: {
            if (visible) {
                closeOnNodeSaveSuccess = false
                clearForm()
                var nodeDefault = bridge ? bridge.settingsNodeVersion : ""
                var idx = nodeVersionCombo.find(nodeDefault)
                if (idx >= 0) {
                    nodeVersionCombo.currentIndex = idx
                }
            }
        }

        onClosing: function() {
            closeOnNodeSaveSuccess = false
            root.addNodeProjectOpen = false
        }

        function clearForm() {
            root.addNodeProjectFeedback = ""
            root.addNodeProjectFeedbackError = false
            nodeDomainField.text = ""
            nodeProjectPathField.text = ""
            nodeDetectedPortField.text = ""
            nodeRunOptionsCombo.currentIndex = -1
            nodeRunCommandText = ""
            nodeNotesField.text = ""
            nodeSslCheckbox.checked = false
            nodePathValidationText = ""
            nodePathValidationError = false
            nodePathValid = false
            nodeDomainValidationText = ""
            nodeDomainValidationError = false
            nodeRunScriptItems = []
        }

        function inspectNodeProjectPath() {
            var path = nodeProjectPathField.text.trim()
            if (path.length === 0) {
                nodePathValidationText = "Project path is required."
                nodePathValidationError = true
                nodePathValid = false
                nodeRunScriptItems = []
                nodeDetectedPortField.text = ""
                nodeRunOptionsCombo.currentIndex = -1
                nodeRunCommandText = ""
                return
            }
            var result = bridge ? bridge.inspectNodeProject(path) : ({ valid: false, message: Strings.t("project.path.is.required"), scripts: [], port: "" })
            nodePathValid = !!result.valid
            nodePathValidationText = String(result.message || "")
            nodePathValidationError = !nodePathValid
            nodeRunScriptItems = nodePathValid ? (result.scripts || []) : []
            if (nodeRunScriptItems.length > 0) {
                nodeRunOptionsCombo.currentIndex = 0
                var selected = nodeRunScriptItems[0] || {}
                nodeDetectedPortField.text = String(selected.port || result.port || "")
                nodeRunCommandText = String(selected.command || "")
            } else {
                nodeRunOptionsCombo.currentIndex = -1
                nodeDetectedPortField.text = String(result.port || "")
                nodeRunCommandText = ""
            }
        }

        function confirmNodeProjectDialog() {
            if (nodeProjectSaveBusy) {
                return
            }
            if (root.nodeDomainExists(nodeDomainField.text)) {
                root.addNodeProjectFeedback = "Domain already exists. Use a unique domain."
                root.addNodeProjectFeedbackError = true
                return
            }
            if (nodeVersionCombo.currentIndex < 0) {
                root.addNodeProjectFeedback = "Please select a Node runtime."
                root.addNodeProjectFeedbackError = true
                return
            }
            if (nodeRunOptionsCombo.currentIndex < 0 || nodeRunOptionsCombo.currentIndex >= nodeRunScriptItems.length) {
                root.addNodeProjectFeedback = "Please select run option."
                root.addNodeProjectFeedbackError = true
                return
            }
            var selectedRun = nodeRunScriptItems[nodeRunOptionsCombo.currentIndex] || {}
            var payload = {
                name: root.siteNameFromDomain(nodeDomainField.text.trim()),
                local_domain: nodeDomainField.text.trim(),
                project_path: nodeProjectPathField.text.trim(),
                node_version: nodeVersionCombo.currentText,
                run_script_name: String(selectedRun.name || ""),
                run_script_command: String(selectedRun.command || ""),
                port: nodeDetectedPortField.text.trim(),
                notes: nodeNotesField.text.trim(),
                ssl_enabled: nodeSslCheckbox.checked
            }
            addNodeProjectWindow.closeOnNodeSaveSuccess = true
            if (!bridge || !bridge.saveNodeProjectAsync(payload)) {
                root.addNodeProjectFeedback = bridge ? bridge.lastOperationMessage : ""
                root.addNodeProjectFeedbackError = true
            }
        }

        Components.AppWindowFrame {
            title: "Create Node Project Mapping"
            moveWindow: addNodeProjectWindow
            contentMargins: 24
            contentSpacing: 12
            footerRightMargin: contentMargins
            footerBottomMargin: contentMargins

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                Text {
                    text: Strings.t("map.a.local.node.app.through.server.engine.with.a.local.domain.selected.node.runtime.detected.package.script.port.tracking.and.runtime.controls")
                    color: Theme.muted
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    columnSpacing: 18
                    rowSpacing: 14

                    Label { text: Strings.t("domain"); Layout.preferredWidth: root.createSiteLabelWidth; Layout.minimumWidth: root.createSiteLabelWidth; color: Theme.text; font.pixelSize: 14; font.weight: Font.Medium }
                    Components.AppTextField {
                        id: nodeDomainField
                        Layout.fillWidth: true
                        placeholderText: Strings.t("myapp.engine")
                        inputMethodHints: Qt.ImhLowercaseOnly | Qt.ImhNoPredictiveText
                        validator: RegularExpressionValidator { regularExpression: /^[a-z0-9.-]*$/ }
                        onTextEdited: {
                            var cleaned = root.sanitizeLocalDomain(text)
                            if (cleaned !== text) {
                                text = cleaned
                            }
                        }
                        onTextChanged: {
                            if (root.nodeDomainExists(text)) {
                                addNodeProjectWindow.nodeDomainValidationText = "Domain already exists."
                                addNodeProjectWindow.nodeDomainValidationError = true
                            } else {
                                addNodeProjectWindow.nodeDomainValidationText = ""
                                addNodeProjectWindow.nodeDomainValidationError = false
                            }
                        }
                    }

                    Label { text: Strings.t("project.folder"); Layout.preferredWidth: root.createSiteLabelWidth; Layout.minimumWidth: root.createSiteLabelWidth; color: Theme.text; font.pixelSize: 14; font.weight: Font.Medium }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Components.AppTextField {
                            id: nodeProjectPathField
                            Layout.fillWidth: true
                            placeholderText: Strings.t("users.you.projects.my.node.app")
                            readOnly: true
                        }
                        Components.AppButton {
                            text: Strings.t("choose")
                            onClicked: nodeFolderDialog.open()
                        }
                    }

                    Label { text: Strings.t("node.version"); Layout.preferredWidth: root.createSiteLabelWidth; Layout.minimumWidth: root.createSiteLabelWidth; color: Theme.text; font.pixelSize: 14; font.weight: Font.Medium }
                    Components.AppComboBox {
                        id: nodeVersionCombo
                        Layout.fillWidth: true
                        Layout.maximumWidth: 240
                        model: bridge ? bridge.nodeRuntimeVersions : []
                    }

                    Text {
                        visible: !bridge || bridge.nodeRuntimeVersions.length === 0
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        text: Strings.t("no.node.runtime.installed.a.href.install.node.install.one.in.runtime.manager.a")
                        textFormat: Text.RichText
                        linkColor: Theme.accentStrong
                        color: Theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        onLinkActivated: function(_link) { root.installNodeRuntimeRequested() }
                    }

                    Label { text: Strings.t("port"); Layout.preferredWidth: root.createSiteLabelWidth; Layout.minimumWidth: root.createSiteLabelWidth; color: Theme.text; font.pixelSize: 14; font.weight: Font.Medium }
                    Components.AppTextField { id: nodeDetectedPortField; Layout.fillWidth: true; inputMethodHints: Qt.ImhDigitsOnly; placeholderText: Strings.t("auto.detected.editable") }

                    Label { text: Strings.t("run.options"); Layout.preferredWidth: root.createSiteLabelWidth; Layout.minimumWidth: root.createSiteLabelWidth; color: Theme.text; font.pixelSize: 14; font.weight: Font.Medium }
                    Components.AppComboBox {
                        id: nodeRunOptionsCombo
                        Layout.fillWidth: true
                        model: addNodeProjectWindow.nodeRunScriptItems
                        textRole: "label"
                        onCurrentIndexChanged: {
                            if (currentIndex < 0 || currentIndex >= addNodeProjectWindow.nodeRunScriptItems.length) {
                                addNodeProjectWindow.nodeRunCommandText = ""
                                return
                            }
                            var selected = addNodeProjectWindow.nodeRunScriptItems[currentIndex] || {}
                            if (String(selected.port || "").length > 0) {
                                nodeDetectedPortField.text = String(selected.port)
                            }
                            addNodeProjectWindow.nodeRunCommandText = String(selected.command || "")
                        }
                    }

                    Label { text: Strings.t("note"); Layout.preferredWidth: root.createSiteLabelWidth; Layout.minimumWidth: root.createSiteLabelWidth; color: Theme.text; font.pixelSize: 14; font.weight: Font.Medium }
                    Components.AppTextField { id: nodeNotesField; Layout.fillWidth: true; placeholderText: Strings.t("optional.note") }

                    Item { Layout.preferredWidth: root.createSiteLabelWidth; Layout.minimumWidth: root.createSiteLabelWidth; height: 1 }
                    Components.AppCheckBox {
                        id: nodeSslCheckbox
                        text: Strings.t("enable.ssl")
                    }
                }
            }

            footerLeft: Text {
                visible: addNodeProjectWindow.footerStatusText.length > 0
                text: addNodeProjectWindow.footerStatusText
                color: addNodeProjectWindow.footerStatusError ? "#bb4d4d" : "#4aa94b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            footerRight: Row {
                spacing: 8
                Components.AppButton {
                    text: Strings.t("cancel")
                    enabled: !addNodeProjectWindow.nodeProjectSaveBusy
                    onClicked: root.addNodeProjectOpen = false
                }
                Components.AppButton {
                    text: Strings.t("add.project")
                    highlighted: true
                    textColor: "white"
                    enabled: addNodeProjectWindow.confirmEnabled
                    onClicked: addNodeProjectWindow.confirmNodeProjectDialog()
                }
            }
        }

        FolderDialog {
            id: nodeFolderDialog
            title: Strings.t("choose.node.project.folder")
            parentWindow: addNodeProjectWindow
            onAccepted: {
                nodeProjectPathField.text = root.folderPathFromUrl(selectedFolder)
                addNodeProjectWindow.inspectNodeProjectPath()
            }
        }
    }
}
