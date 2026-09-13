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

    property alias closeOnNodeSaveSuccess: addNodeProjectWindow.closeOnNodeSaveSuccess
    property alias confirmEnabled: addNodeProjectWindow.confirmEnabled
    property alias nodeProjectSaveBusy: addNodeProjectWindow.nodeProjectSaveBusy
    property alias nodeRuntimeActionBusy: addNodeProjectWindow.nodeRuntimeActionBusy
    property alias nodeRuntimeRunning: addNodeProjectWindow.nodeRuntimeRunning

    property string nodeDomainText: ""
    property alias nodeProjectPathField: nodeProjectPathField
    property alias nodeDetectedPortField: nodeDetectedPortField
    property alias nodeNotesField: nodeNotesField
    property alias nodeVersionCombo: nodeVersionCombo
    property alias nodeRunOptionsCombo: nodeRunOptionsCombo
    property string addNodeProjectFeedback: root ? root.addNodeProjectFeedback : ""
    property bool addNodeProjectFeedbackError: root ? root.addNodeProjectFeedbackError : false
    property string editingNodeProjectId: root ? root.editingNodeProjectId : ""
    property alias nodeSslEnabled: addNodeProjectWindow.nodeSslEnabled
    property alias nodeSslEnforceTls: addNodeProjectWindow.nodeSslEnforceTls
    property alias nodeSslAllowHttp: addNodeProjectWindow.nodeSslAllowHttp
    property alias nodeSslCertificatePath: addNodeProjectWindow.nodeSslCertificatePath
    property alias nodeSslKeyPath: addNodeProjectWindow.nodeSslKeyPath
    property alias nodeSslCertificateExists: addNodeProjectWindow.nodeSslCertificateExists

    function refreshNodeRuntime() { addNodeProjectWindow.refreshNodeRuntime() }
    function inspectNodeProjectPath() { addNodeProjectWindow.inspectNodeProjectPath() }
    function cancelNodeProjectDialog() { addNodeProjectWindow.cancelNodeProjectDialog() }
    function confirmNodeProjectDialog() { addNodeProjectWindow.confirmNodeProjectDialog() }
    function saveNodeProjectConfig() { addNodeProjectWindow.saveNodeProjectConfig() }
    function refreshNodeProjectDetails() { addNodeProjectWindow.refreshNodeProjectDetails() }
    function sanitizeLocalDomain(value) { return root && root.sanitizeLocalDomain ? root.sanitizeLocalDomain(value) : String(value || "").trim().toLowerCase().replace(/[^a-z0-9.-]/g, "") }
    function nodeDomainExists(value) { return root && root.nodeDomainExists ? root.nodeDomainExists(value) : false }
    function setNodeSslEnabled(value) { addNodeProjectWindow.nodeSslEnabled = !!value }
    function setNodeSslEnforceTls(value) { addNodeProjectWindow.nodeSslEnforceTls = !!value }
    function setNodeSslAllowHttp(value) { addNodeProjectWindow.nodeSslAllowHttp = !!value }
    function createNodeProjectCertificate() { addNodeProjectWindow.createNodeProjectCertificate() }
    function trustNodeProjectCertificate() { addNodeProjectWindow.trustNodeProjectCertificate() }
    function applyNodeProjectWindowHeight(sectionId) { addNodeProjectWindow.applyNodeProjectWindowHeight(sectionId) }
    function updateNodeProjectConfirmEnabled() {
        addNodeProjectWindow.confirmEnabled = nodeDomainText.trim().length > 0
            && nodeProjectPathField.text.trim().length > 0
            && nodeVersionCombo.currentIndex >= 0
            && nodeRunOptionsCombo.currentIndex >= 0
            && addNodeProjectWindow.nodePathValid
            && !nodeProjectSaveBusy
    }
    function openNodeProject(nodeItem) {
        var item = nodeItem || ({})
        addNodeProjectWindow.closeOnNodeSaveSuccess = false
        root.addNodeProjectOpen = false
        root.editNodeProjectMode = true
        root.editingNodeProjectId = String(item.id || "")
        root.addNodeProjectFeedback = ""
        root.addNodeProjectFeedbackError = false
        root.nodeProjectDialogSection = "domain"
        nodeDomainText = String(item.domain || "")
        nodeProjectPathField.text = String(item.project_path || "")
        nodeDetectedPortField.text = String(item.port || "")
        nodeNotesField.text = String(item.note || "")
        addNodeProjectWindow.nodePathValid = false
        addNodeProjectWindow.nodePathValidationText = ""
        addNodeProjectWindow.nodePathValidationError = false
        addNodeProjectWindow.nodeRunScriptItems = []
        nodeRunOptionsCombo.currentIndex = -1
        addNodeProjectWindow.nodeRunCommandText = ""
        addNodeProjectWindow.nodeSslEnabled = item.ssl_enabled !== undefined ? !!item.ssl_enabled : String(item.ssl || "") === "On"
        addNodeProjectWindow.nodeSslEnforceTls = !!item.ssl_enforce_tls
        addNodeProjectWindow.nodeSslAllowHttp = item.ssl_allow_http !== undefined ? !!item.ssl_allow_http : true
        addNodeProjectWindow.nodeSslCertificatePath = String(item.ssl_certificate_path || "")
        addNodeProjectWindow.nodeSslKeyPath = String(item.ssl_key_path || "")
        addNodeProjectWindow.nodeSslCertificateExists = !!item.ssl_certificate_exists
        var nodeIdx = nodeVersionCombo.find(String(item.node_version || ""))
        if (nodeIdx >= 0) {
            nodeVersionCombo.currentIndex = nodeIdx
        }
        nodeProjectOpenRefreshTimer.restart()
    }

    Window {
        id: addNodeProjectWindow
        property bool confirmEnabled: false
        width: 800
        height: 560
        minimumWidth: width
        maximumWidth: width

        minimumHeight: 420
        maximumHeight: 820
        visible: root.editNodeProjectMode
        title: "Modify Node Project"
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
        modality: Qt.ApplicationModal
        color: Theme.surface
        readonly property bool nodeRuntimeActionBusy: bridge ? bridge.nodeProjectRuntimeActionBusy : false
        readonly property bool nodeProjectSaveBusy: bridge ? bridge.nodeProjectSaveBusy : false
        property bool closeOnNodeSaveSuccess: false
        property bool nodeRuntimeRunning: nodeProjectRuntimeSection.nodeRuntimeRunning
        property bool nodePathValid: false
        property string nodeRunCommandText: ""
        property string nodeDomainValidationText: ""
        property bool nodeDomainValidationError: false
        property string nodePathValidationText: ""
        property bool nodePathValidationError: false
        property var nodeRunScriptItems: []
        property bool nodeSslEnabled: false
        property bool nodeSslEnforceTls: false
        property bool nodeSslAllowHttp: true
        property string nodeSslCertificatePath: ""
        property string nodeSslKeyPath: ""
        property bool nodeSslCertificateExists: false
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

        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        function applyNodeProjectWindowHeight(sectionId) {
            var nextHeight = 560
            switch (String(sectionId || "")) {
            case "domain":
                nextHeight = 520
                break
            case "service":
                nextHeight = 430
                break
            case "modules":
                nextHeight = 620
                break
            case "logs":
            case "response.log":
                nextHeight = 640
                break
            case "configuration":
            default:
                nextHeight = 720
                break
            }
            nextHeight = Math.max(minimumHeight, Math.min(maximumHeight, nextHeight))
            if (height !== nextHeight) {
                height = nextHeight
            }
        }

        onVisibleChanged: {
            if (visible) {
                closeOnNodeSaveSuccess = false
                root.addNodeProjectFeedback = ""
                root.addNodeProjectFeedbackError = false
                root.nodeProjectDialogSection = "domain"
                Qt.callLater(function() {
                    addNodeProjectWindow.applyNodeProjectWindowHeight(root.nodeProjectDialogSection)
                })
            }
        }

        onClosing: function(closeEvent) {
            closeOnNodeSaveSuccess = false
            nodeProjectModulesRefreshTimer.stop()
            root.editNodeProjectMode = false
            root.editingNodeProjectId = ""
            root.nodeProjectDialogSection = "configuration"
        }

        Connections {
            target: root
            function onNodeProjectDialogSectionChanged() {
                if (root.editNodeProjectMode) {
                    addNodeProjectWindow.applyNodeProjectWindowHeight(root.nodeProjectDialogSection)
                }
                if (root.editNodeProjectMode && root.nodeProjectDialogSection === "modules") {
                    nodeProjectModulesRefreshTimer.restart()
                } else if (root.editNodeProjectMode && (root.nodeProjectDialogSection === "logs" || root.nodeProjectDialogSection === "response.log")) {
                    Qt.callLater(function() {
                        if (root.nodeProjectDialogSection === "logs") {
                            if (nodeProjectLogsLoader && nodeProjectLogsLoader.item && nodeProjectLogsLoader.item.loadLogs) {
                                nodeProjectLogsLoader.item.loadLogs()
                            }
                        } else {
                            if (nodeProjectResponseLogsLoader && nodeProjectResponseLogsLoader.item && nodeProjectResponseLogsLoader.item.loadLogs) {
                                nodeProjectResponseLogsLoader.item.loadLogs()
                            }
                        }
                    })
                }
            }
        }

        Timer {
            id: nodeProjectOpenRefreshTimer
            interval: 120
            repeat: false
            running: false
            onTriggered: {
                addNodeProjectWindow.inspectNodeProjectPath()
                addNodeProjectWindow.refreshNodeProjectDetails()
                addNodeProjectWindow.refreshNodeRuntime()
                addNodeProjectWindow.applyNodeProjectWindowHeight(root.nodeProjectDialogSection)
            }
        }

        Timer {
            id: nodeProjectModulesRefreshTimer
            interval: 150
            repeat: false
            running: false
            onTriggered: {
                if (root.editNodeProjectMode && root.nodeProjectDialogSection === "modules") {
                    addNodeProjectWindow.loadNodeProjectModules()
                }
            }
        }

    function confirmNodeProjectDialog() {
        if (nodeProjectSaveBusy) {
            return
        }
        saveNodeProjectConfig()
    }

    function loadNodeProjectModules() {
        if (nodeProjectModulesLoader && nodeProjectModulesLoader.item && nodeProjectModulesLoader.item.loadModules) {
            nodeProjectModulesLoader.item.loadModules()
        }
    }

    function refreshNodeProjectDetails() {
        if (!bridge || !root.editNodeProjectMode || root.editingNodeProjectId.length === 0) {
            return
        }
        var details = bridge.nodeProjectDetails(root.editingNodeProjectId)
        if (!details || !details.id) {
            return
        }
        nodeSslEnabled = !!details.ssl_enabled
        nodeSslEnforceTls = !!details.ssl_enforce_tls
        nodeSslAllowHttp = details.ssl_allow_http !== undefined ? !!details.ssl_allow_http : true
        nodeSslCertificatePath = String(details.ssl_certificate_path || "")
        nodeSslKeyPath = String(details.ssl_key_path || "")
        nodeSslCertificateExists = !!details.ssl_certificate_exists
    }

        function cancelNodeProjectDialog() {
            root.editNodeProjectMode = false
            root.editingNodeProjectId = ""
            root.addNodeProjectOpen = false
        }

        function inspectNodeProjectPath() {
            var path = nodeProjectPathField.text.trim()
            if (path.length === 0) {
                addNodeProjectWindow.nodePathValidationText = "Project path is required."
                addNodeProjectWindow.nodePathValidationError = true
                addNodeProjectWindow.nodePathValid = false
                addNodeProjectWindow.nodeRunScriptItems = []
                nodeDetectedPortField.text = ""
                nodeRunOptionsCombo.currentIndex = -1
                addNodeProjectWindow.nodeRunCommandText = ""
                updateNodeProjectConfirmEnabled()
                return
            }
            var result = bridge ? bridge.inspectNodeProject(path) : ({ valid: false, message: Strings.t("project.path.is.required"), scripts: [], port: "" })
            var isValid = !!result.valid
            addNodeProjectWindow.nodePathValid = isValid
            addNodeProjectWindow.nodePathValidationText = String(result.message || "")
            addNodeProjectWindow.nodePathValidationError = !isValid
            addNodeProjectWindow.nodeRunScriptItems = isValid ? (result.scripts || []) : []
            if (addNodeProjectWindow.nodeRunScriptItems.length > 0) {
                var selectedIndex = 0
                var selectedName = String(result.script_name || "")
                for (var i = 0; i < addNodeProjectWindow.nodeRunScriptItems.length; i++) {
                    if (String(addNodeProjectWindow.nodeRunScriptItems[i].name || "") === selectedName) {
                        selectedIndex = i
                        break
                    }
                }
                nodeRunOptionsCombo.currentIndex = selectedIndex
                var selected = addNodeProjectWindow.nodeRunScriptItems[selectedIndex] || {}
                nodeDetectedPortField.text = String(selected.port || result.port || "")
                addNodeProjectWindow.nodeRunCommandText = String(selected.command || "")
            } else {
                nodeRunOptionsCombo.currentIndex = -1
                nodeDetectedPortField.text = String(result.port || "")
                addNodeProjectWindow.nodeRunCommandText = ""
            }
            updateNodeProjectConfirmEnabled()
        }

        function saveNodeProjectConfig() {
            if (!nodeProjectSaveBusy) {
                var payload = buildNodeProjectPayload()
            if (!payload) {
                return
            }
            addNodeProjectWindow.closeOnNodeSaveSuccess = false
            if (!bridge || !bridge.saveNodeProjectAsync(payload)) {
                root.addNodeProjectFeedback = bridge ? bridge.lastOperationMessage : ""
                root.addNodeProjectFeedbackError = true
            }
        }
    }

        function saveNodeProjectSsl() {
        if (nodeProjectSaveBusy) {
            return
        }
        var payload = buildNodeProjectPayload()
        if (!payload) {
            return
        }
        addNodeProjectWindow.closeOnNodeSaveSuccess = false
        if (!bridge || !bridge.saveNodeProjectAsync(payload)) {
            root.addNodeProjectFeedback = bridge ? bridge.lastOperationMessage : ""
            root.addNodeProjectFeedbackError = true
        }
    }

    function createNodeProjectCertificate() {
        if (nodeProjectSaveBusy || !bridge || root.editingNodeProjectId.length === 0) {
            return
        }
        var ok = bridge.createNodeProjectSelfSignedCertificate(root.editingNodeProjectId)
        root.addNodeProjectFeedback = bridge.lastOperationMessage
        root.addNodeProjectFeedbackError = !ok
        if (ok) {
            nodeSslCertificateExists = true
            refreshNodeProjectDetails()
        }
    }

    function trustNodeProjectCertificate() {
        if (nodeProjectSaveBusy || !bridge || root.editingNodeProjectId.length === 0) {
            return
        }
        var ok = bridge.trustNodeProjectCertificate(root.editingNodeProjectId)
        root.addNodeProjectFeedback = bridge.lastOperationMessage
        root.addNodeProjectFeedbackError = !ok
    }

        function buildNodeProjectPayload() {
        if (!nodeDomainText || nodeDomainText.trim().length === 0) {
            root.addNodeProjectFeedback = "Domain cannot be empty."
            root.addNodeProjectFeedbackError = true
            return null
        }
        if (root.nodeDomainExists(nodeDomainText)) {
            root.addNodeProjectFeedback = "Domain already exists. Use a unique domain."
            root.addNodeProjectFeedbackError = true
            return null
        }
        if (nodeVersionCombo.currentIndex < 0) {
            root.addNodeProjectFeedback = "Please select a Node runtime."
            root.addNodeProjectFeedbackError = true
            return null
        }
        if (nodeRunOptionsCombo.currentIndex < 0 || nodeRunOptionsCombo.currentIndex >= addNodeProjectWindow.nodeRunScriptItems.length) {
            root.addNodeProjectFeedback = "Please select run option."
            root.addNodeProjectFeedbackError = true
            return null
        }
        var selectedRun = addNodeProjectWindow.nodeRunScriptItems[nodeRunOptionsCombo.currentIndex] || {}
        return {
            id: root.editingNodeProjectId,
            name: root.siteNameFromDomain(nodeDomainText.trim()),
            local_domain: nodeDomainText.trim(),
            project_path: nodeProjectPathField.text.trim(),
            node_version: nodeVersionCombo.currentText,
            run_script_name: String(selectedRun.name || ""),
            run_script_command: String(selectedRun.command || ""),
            port: nodeDetectedPortField.text.trim(),
            notes: nodeNotesField.text.trim(),
            ssl_enabled: nodeSslEnabled,
            ssl_enforce_tls: nodeSslEnforceTls,
            ssl_allow_http: nodeSslAllowHttp,
            template_id: "existing"
        }
    }

        function refreshNodeRuntime() {
            if (!root.editNodeProjectMode || root.editingNodeProjectId.length === 0) {
                return
            }
            var currentState = bridge ? bridge.nodeProjectServiceState(root.editingNodeProjectId) : ({})
            nodeProjectRuntimeSection.setRuntimeState(currentState)
            if (root.nodeProjectDialogSection === "logs") {
                if (nodeProjectLogsLoader && nodeProjectLogsLoader.item && nodeProjectLogsLoader.item.loadLogs) {
                    nodeProjectLogsLoader.item.loadLogs()
                }
            } else if (root.nodeProjectDialogSection === "response.log") {
                if (nodeProjectResponseLogsLoader && nodeProjectResponseLogsLoader.item && nodeProjectResponseLogsLoader.item.loadLogs) {
                    nodeProjectResponseLogsLoader.item.loadLogs()
                }
            }
            if (bridge && bridge.nodeProjectRuntimeMessage.length > 0) {
                root.addNodeProjectFeedback = bridge.nodeProjectRuntimeMessage
                root.addNodeProjectFeedbackError = bridge.nodeProjectRuntimeError
            }
        }

        function invokeNodeRuntimeAction(actionName) {
            if (nodeRuntimeActionBusy || !root.editNodeProjectMode || root.editingNodeProjectId.length === 0) {
                return
            }
            var started = false
            if (actionName === "start") {
                started = bridge ? bridge.startNodeProjectRuntimeAsync(root.editingNodeProjectId) : false
            } else if (actionName === "stop") {
                started = bridge ? bridge.stopNodeProjectRuntimeAsync(root.editingNodeProjectId) : false
            } else if (actionName === "restart") {
                started = bridge ? bridge.restartNodeProjectRuntimeAsync(root.editingNodeProjectId) : false
            }
            if (!started) {
                root.addNodeProjectFeedback = bridge ? bridge.lastOperationMessage : ""
                root.addNodeProjectFeedbackError = true
            }
        }

        function nodeDialogSectionIcon(sectionId) {
            if (sectionId === "service") {
                return "power-accent"
            }
            if (sectionId === "domain") {
                return "globe"
            }
            if (sectionId === "modules") {
                return "package"
            }
            if (sectionId === "logs") {
                return "file-text"
            }
            if (sectionId === "response.log") {
                return "activity"
            }
            return "settings"
        }

        Components.AppWindowFrame {
            title: root.editNodeProjectMode ? "" : "Create Node Project Mapping"
            moveWindow: addNodeProjectWindow
            contentMargins: root.editNodeProjectMode ? 0 : 24
            contentSpacing: 12
            footerRightMargin: root.editNodeProjectMode ? 20 : contentMargins
            footerBottomMargin: root.editNodeProjectMode ? 20 : contentMargins

            ColumnLayout {
                anchors.fill: parent
                spacing: root.editNodeProjectMode ? 0 : 10

                Rectangle {
                    visible: root.editNodeProjectMode
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    Layout.topMargin: root.editNodeProjectMode ? -44 : 0
                    color: Theme.titleBar
                    radius: 0

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.border
                    }

                    Text {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 16
                        text: root.nodeProjectDialogSection === "logs"
                            ? "Logs"
                            : (root.nodeProjectDialogSection === "response.log"
                                ? "Response Log"
                                : (root.nodeProjectDialogSection === "modules"
                                    ? "Modules"
                                    : (root.nodeProjectDialogSection === "domain"
                                        ? "Domain"
                                        : (root.nodeProjectDialogSection === "service" ? "Service" : "Configuration"))))
                        color: Theme.text
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Row {
                        anchors.fill: parent
                        anchors.topMargin: 40
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.bottomMargin: 6
                        spacing: 6

                        Components.TopIconTab {
                            label: Strings.t("domain")
                            selected: root.nodeProjectDialogSection === "domain"
                            iconSource: "../icons/lucide/" + addNodeProjectWindow.nodeDialogSectionIcon("domain") + ".svg"
                            onClicked: root.nodeProjectDialogSection = "domain"
                        }

                        Components.TopIconTab {
                            label: Strings.t("service")
                            selected: root.nodeProjectDialogSection === "service"
                            iconSource: "../icons/lucide/" + addNodeProjectWindow.nodeDialogSectionIcon("service") + ".svg"
                            onClicked: root.nodeProjectDialogSection = "service"
                        }

                        Components.TopIconTab {
                            label: Strings.t("configuration")
                            selected: root.nodeProjectDialogSection === "configuration"
                            iconSource: "../icons/lucide/" + addNodeProjectWindow.nodeDialogSectionIcon("configuration") + ".svg"
                            onClicked: root.nodeProjectDialogSection = "configuration"
                        }

                        Components.TopIconTab {
                            label: "Modules"
                            selected: root.nodeProjectDialogSection === "modules"
                            iconSource: "../icons/lucide/" + addNodeProjectWindow.nodeDialogSectionIcon("modules") + ".svg"
                            onClicked: root.nodeProjectDialogSection = "modules"
                        }

                        Components.TopIconTab {
                            visible: root.editNodeProjectMode
                            label: Strings.t("logs")
                            selected: root.nodeProjectDialogSection === "logs"
                            iconSource: "../icons/lucide/" + addNodeProjectWindow.nodeDialogSectionIcon("logs") + ".svg"
                            onClicked: {
                                root.nodeProjectDialogSection = "logs"
                                Qt.callLater(function() {
                                    if (nodeProjectLogsLoader && nodeProjectLogsLoader.item && nodeProjectLogsLoader.item.loadLogs) {
                                        nodeProjectLogsLoader.item.loadLogs()
                                    }
                                })
                            }
                        }

                        Components.TopIconTab {
                            label: Strings.t("response.log")
                            selected: root.nodeProjectDialogSection === "response.log"
                            iconSource: "../icons/lucide/" + addNodeProjectWindow.nodeDialogSectionIcon("response.log") + ".svg"
                            onClicked: root.nodeProjectDialogSection = "response.log"
                        }
                    }
                }

                Text {
                    visible: !root.editNodeProjectMode
                    text: Strings.t("map.a.local.node.app.through.server.engine.with.a.local.domain.selected.node.runtime.detected.package.script.port.tracking.and.runtime.controls")
                    color: Theme.muted
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.editNodeProjectMode && root.nodeProjectDialogSection === "logs"
                    Layout.maximumHeight: visible ? Number.POSITIVE_INFINITY : 0
                    Layout.leftMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.rightMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.topMargin: root.editNodeProjectMode ? 16 : 0
                    Layout.bottomMargin: root.editNodeProjectMode ? 20 : 0
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Loader {
                            id: nodeProjectLogsLoader
                            anchors.fill: parent
                            active: root.editNodeProjectMode && root.nodeProjectDialogSection === "logs"
                            sourceComponent: NodeProjectLogsSection {
                                pageRoot: root
                                dashboardBridge: bridge
                                runtimeWindow: addNodeProjectWindow
                                projectId: root.editingNodeProjectId
                            }
                            onLoaded: {
                                if (item && item.loadLogs) {
                                    Qt.callLater(function() {
                                        item.loadLogs()
                                    })
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.editNodeProjectMode && root.nodeProjectDialogSection === "domain"
                    Layout.maximumHeight: visible ? Number.POSITIVE_INFINITY : 0
                    Layout.leftMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.rightMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.topMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.bottomMargin: root.editNodeProjectMode ? 20 : 0
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Loader {
                            id: nodeProjectDomainLoader
                            anchors.fill: parent
                            active: root.editNodeProjectMode && root.nodeProjectDialogSection === "domain"
                            sourceComponent: NodeProjectDomainSection {
                                pageRoot: host
                                dashboardBridge: bridge
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.editNodeProjectMode && root.nodeProjectDialogSection === "modules"
                    Layout.maximumHeight: visible ? Number.POSITIVE_INFINITY : 0
                    Layout.leftMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.rightMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.topMargin: root.editNodeProjectMode ? 16 : 0
                    Layout.bottomMargin: root.editNodeProjectMode ? 20 : 0
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Loader {
                            id: nodeProjectModulesLoader
                            anchors.fill: parent
                            active: root.editNodeProjectMode && root.nodeProjectDialogSection === "modules"
                            sourceComponent: NodeProjectModulesSection {
                                pageRoot: root
                                dashboardBridge: bridge
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.editNodeProjectMode && root.nodeProjectDialogSection === "response.log"
                    Layout.maximumHeight: visible ? Number.POSITIVE_INFINITY : 0
                    Layout.leftMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.rightMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.topMargin: root.editNodeProjectMode ? 16 : 0
                    Layout.bottomMargin: root.editNodeProjectMode ? 20 : 0
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Loader {
                            id: nodeProjectResponseLogsLoader
                            anchors.fill: parent
                            active: root.editNodeProjectMode && root.nodeProjectDialogSection === "response.log"
                            sourceComponent: NodeProjectResponseLogSection {
                                pageRoot: root
                                dashboardBridge: bridge
                                projectId: root.editingNodeProjectId
                            }
                            onLoaded: {
                                if (item && item.loadLogs) {
                                    Qt.callLater(function() {
                                        item.loadLogs()
                                    })
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.editNodeProjectMode && root.nodeProjectDialogSection === "service"
                    Layout.maximumHeight: visible ? Number.POSITIVE_INFINITY : 0
                    Layout.leftMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.rightMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.topMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.bottomMargin: root.editNodeProjectMode ? 20 : 0
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        NodeProjectRuntimeSection {
                            id: nodeProjectRuntimeSection
                            anchors.fill: parent
                            pageRoot: host
                            addNodeProjectWindow: addNodeProjectWindow
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.editNodeProjectMode || root.nodeProjectDialogSection === "configuration"
                    Layout.maximumHeight: visible ? Number.POSITIVE_INFINITY : 0
                    Layout.leftMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.rightMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.topMargin: root.editNodeProjectMode ? 20 : 0
                    Layout.bottomMargin: root.editNodeProjectMode ? 20 : 0
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Components.SettingsTabFrame {
                            anchors.fill: parent
                            color: "transparent"

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 14

                                Components.SettingsLabeledControl {
                                    title: Strings.t("project.folder")
                                    description: "Choose the local folder that contains the Node project."

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
                                }

                                Components.SettingsLabeledControl {
                                    title: Strings.t("node.version")
                                    description: "Select the Node runtime that should run this project."

                                    Components.AppComboBox {
                                        id: nodeVersionCombo
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 240
                                        model: bridge ? bridge.nodeRuntimeVersions : []
                                        onCurrentIndexChanged: updateNodeProjectConfirmEnabled()
                                    }
                                }

                                Text {
                                    visible: !bridge || bridge.nodeRuntimeVersions.length === 0
                                    Layout.fillWidth: true
                                    text: Strings.t("no.node.runtime.installed.a.href.install.node.install.one.in.runtime.manager.a")
                                    textFormat: Text.RichText
                                    linkColor: Theme.accentStrong
                                    color: Theme.muted
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    onLinkActivated: function(_link) {
                                        root.installNodeRuntimeRequested()
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    title: Strings.t("port")
                                    description: "Use the detected port or type a custom one."

                                    Components.AppTextField {
                                        id: nodeDetectedPortField
                                        Layout.fillWidth: true
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        placeholderText: Strings.t("auto.detected.editable")
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    title: Strings.t("run.options")
                                    description: "Choose which package script should start the app."

                                    Components.AppComboBox {
                                        id: nodeRunOptionsCombo
                                        Layout.fillWidth: true
                                        model: addNodeProjectWindow.nodeRunScriptItems
                                        textRole: "label"
                                        onCurrentIndexChanged: {
                                            if (currentIndex < 0 || currentIndex >= addNodeProjectWindow.nodeRunScriptItems.length) {
                                                addNodeProjectWindow.nodeRunCommandText = ""
                                                updateNodeProjectConfirmEnabled()
                                                return
                                            }
                                            var selected = addNodeProjectWindow.nodeRunScriptItems[currentIndex] || {}
                                            if (String(selected.port || "").length > 0) {
                                                nodeDetectedPortField.text = String(selected.port)
                                            }
                                            addNodeProjectWindow.nodeRunCommandText = String(selected.command || "")
                                            updateNodeProjectConfirmEnabled()
                                        }
                                    }
                                }

                                Components.SettingsLabeledControl {
                                    title: Strings.t("note")
                                    description: "Optional note for this Node project."

                                    Components.AppTextField {
                                        id: nodeNotesField
                                        Layout.fillWidth: true
                                        placeholderText: Strings.t("optional.note")
                                    }
                                }
                            }

                            footerRight: Row {
                                spacing: 8
                                Components.AppButton {
                                    text: Strings.t("test")
                                    enabled: !addNodeProjectWindow.nodeProjectSaveBusy
                                    onClicked: addNodeProjectWindow.inspectNodeProjectPath()
                                }
                                Components.AppButton {
                                    text: Strings.t("settings.appearance.save")
                                    highlighted: true
                                    textColor: "white"
                                    enabled: !addNodeProjectWindow.nodeProjectSaveBusy
                                    onClicked: addNodeProjectWindow.saveNodeProjectConfig()
                                }
                                Components.AppButton {
                                    text: Strings.t("reload")
                                    enabled: !addNodeProjectWindow.nodeProjectSaveBusy
                                    onClicked: addNodeProjectWindow.inspectNodeProjectPath()
                                }
                            }
                        }
                    }
                }
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
