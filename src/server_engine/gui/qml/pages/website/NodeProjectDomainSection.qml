import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root

    required property var pageRoot
    required property var dashboardBridge

    property var domainDraft: []
    property bool sslEnabled: false
    property bool sslEnabledDirty: false
    property bool enforceTls: false
    property bool allowHttp: true
    property bool sslOptionsDirty: false
    property string certFile: ""
    property string keyFile: ""
    property string feedbackText: ""
    property bool feedbackIsError: false

    Timer {
        id: deferredSyncTimer
        interval: 0
        repeat: false
        onTriggered: syncFromNode()
    }

    function normalizedDomain(value) {
        return String(value || "").trim().toLowerCase()
    }

    function hasConflict(domainValue, rowIndex) {
        var value = normalizedDomain(domainValue)
        if (value.length === 0) {
            return ""
        }
        if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/.test(value)) {
            return "Invalid domain format."
        }

        for (var i = 0; i < root.domainDraft.length; i++) {
            if (i === rowIndex) {
                continue
            }
            if (normalizedDomain(root.domainDraft[i]) === value) {
                return "Duplicate domain in this list."
            }
        }

        var websites = dashboardBridge && dashboardBridge.websiteItems ? dashboardBridge.websiteItems : []
        for (var s = 0; s < websites.length; s++) {
            var site = websites[s]
            var domains = site.domains || []
            for (var d = 0; d < domains.length; d++) {
                if (normalizedDomain(domains[d]) === value) {
                    return "Domain already used by another website."
                }
            }
        }

        var nodeProjects = dashboardBridge && dashboardBridge.nodeProjectItems ? dashboardBridge.nodeProjectItems : []
        var currentNodeId = pageRoot && pageRoot.editingNodeProjectId ? String(pageRoot.editingNodeProjectId) : ""
        for (var p = 0; p < nodeProjects.length; p++) {
            var nodeItem = nodeProjects[p]
            if (currentNodeId.length > 0 && String(nodeItem.id || "") === currentNodeId) {
                continue
            }
            if (normalizedDomain(nodeItem.domain) === value) {
                return "Domain already used by a Node project."
            }
        }
        return ""
    }

    function currentStatusText() {
        var conflict = hasConflict(root.domainDraft.length > 0 ? root.domainDraft[0] : "", 0)
        if (conflict.length > 0) {
            return conflict
        }
        if (pageRoot && pageRoot.addNodeProjectFeedback && String(pageRoot.addNodeProjectFeedback).length > 0) {
            return String(pageRoot.addNodeProjectFeedback)
        }
        return root.feedbackText
    }

    function currentStatusIsError() {
        var conflict = hasConflict(root.domainDraft.length > 0 ? root.domainDraft[0] : "", 0)
        if (conflict.length > 0) {
            return true
        }
        if (pageRoot && pageRoot.addNodeProjectFeedback && String(pageRoot.addNodeProjectFeedback).length > 0) {
            return !!pageRoot.addNodeProjectFeedbackError
        }
        return root.feedbackIsError
    }

    function normalizedNodeSslEnabled() {
        return !!(pageRoot && pageRoot.nodeSslEnabled)
    }

    function normalizedNodeEnforceTls() {
        return !!(pageRoot && pageRoot.nodeSslEnforceTls)
    }

    function normalizedNodeAllowHttp() {
        return pageRoot && pageRoot.nodeSslAllowHttp !== undefined ? !!pageRoot.nodeSslAllowHttp : true
    }

    function refreshDirtyState() {
        sslEnabledDirty = sslEnabled !== normalizedNodeSslEnabled()
        sslOptionsDirty = enforceTls !== normalizedNodeEnforceTls() || allowHttp !== normalizedNodeAllowHttp()
    }

    function syncFromNode() {
        var incoming = []
        if (pageRoot && pageRoot.nodeDomainText) {
            incoming = [String(pageRoot.nodeDomainText)]
        }
        if (incoming.length === 0) {
            incoming = [""]
        }
        root.domainDraft = incoming
        sslEnabled = normalizedNodeSslEnabled()
        enforceTls = normalizedNodeEnforceTls()
        allowHttp = normalizedNodeAllowHttp()
        sslEnabledDirty = false
        sslOptionsDirty = false
        certFile = pageRoot && pageRoot.nodeSslCertificatePath ? String(pageRoot.nodeSslCertificatePath) : ""
        keyFile = pageRoot && pageRoot.nodeSslKeyPath ? String(pageRoot.nodeSslKeyPath) : ""
    }

    function fileUrl(path) {
        if (!path || path.length === 0) {
            return ""
        }
        return "file://" + path
    }

    function saveSslSettings() {
        if (!pageRoot || !pageRoot.saveNodeProjectSsl) {
            return
        }
        pageRoot.saveNodeProjectSsl()
    }

    function saveDomainAndSslSettings() {
        if (!pageRoot || !pageRoot.saveNodeProjectSsl) {
            return
        }
        var value = normalizedDomain(root.domainDraft.length > 0 ? root.domainDraft[0] : "")
        if (value.length === 0) {
            root.feedbackText = "Domain cannot be empty."
            root.feedbackIsError = true
            return
        }
        var conflict = root.hasConflict(value, 0)
        if (conflict.length > 0) {
            root.feedbackText = conflict + " (" + value + ")"
            root.feedbackIsError = true
            return
        }
        pageRoot.nodeDomainText = value
        pageRoot.saveNodeProjectSsl()
        if (pageRoot.updateNodeProjectConfirmEnabled) {
            pageRoot.updateNodeProjectConfirmEnabled()
        }
    }

    onPageRootChanged: deferredSyncTimer.restart()
    onDashboardBridgeChanged: deferredSyncTimer.restart()
    Component.onCompleted: deferredSyncTimer.restart()

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            spacing: 16

            Components.SettingsLabeledInput {
                title: Strings.t("domain")
                description: Strings.t("edit.only.the.main.website.domain.for.this.site.advanced.domain.management.is.not.enabled.yet")

                Components.AppTextField {
                    Layout.fillWidth: true
                    placeholderText: "example.engine"
                    text: root.domainDraft.length > 0 ? root.domainDraft[0] : ""
                    validator: RegularExpressionValidator {
                        regularExpression: /^[a-z0-9.-]*$/
                    }
                    onTextEdited: {
                        var cleanedValue = String(text || "").toLowerCase().replace(/[^a-z0-9.-]/g, "")
                        if (cleanedValue !== text) {
                            text = cleanedValue
                        }
                        root.domainDraft = [text]
                        if (pageRoot) {
                            pageRoot.nodeDomainText = text
                            if (pageRoot.updateNodeProjectConfirmEnabled) {
                                pageRoot.updateNodeProjectConfirmEnabled()
                            }
                        }
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: Strings.t("enable.ssl")
                description: "Create a local HTTPS certificate for this site."
                checked: sslEnabled
                itemEnabled: !root.pageRoot.nodeSslCertificateBusy
                onToggled: function(nextChecked) {
                    sslEnabled = nextChecked
                    refreshDirtyState()
                    if (!pageRoot || !pageRoot.createNodeProjectCertificate) {
                        return
                    }
                    if (nextChecked && !(pageRoot.nodeSslCertificateExists !== undefined ? pageRoot.nodeSslCertificateExists : false)) {
                        var started = pageRoot.createNodeProjectCertificateAsync()
                        if (!started) {
                            sslEnabled = false
                            refreshDirtyState()
                            return
                        }
                        certFile = pageRoot.nodeSslCertificatePath ? pageRoot.nodeSslCertificatePath : certFile
                        keyFile = pageRoot.nodeSslKeyPath ? pageRoot.nodeSslKeyPath : keyFile
                    }
                    pageRoot.setNodeSslEnabled(nextChecked)
                }
            }
            Text {
                visible: root.pageRoot.nodeSslCertificateBusy
                text: "Creating SSL certificate..."
                color: Theme.muted
                font.pixelSize: 12
                Layout.fillWidth: true
                Layout.leftMargin: 198
            }

            Components.SettingsLabeledInput {
                title: Strings.t("certificate.file")
                description: "Open the certificate file for this website."

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Components.AppTextField {
                        Layout.fillWidth: true
                        text: root.certFile
                        readOnly: true
                    }

                    Components.AppButton {
                        text: "Reveal in Finder"
                        enabled: root.certFile.length > 0
                        onClicked: {
                            if (dashboardBridge && dashboardBridge.revealInFinder) {
                                dashboardBridge.revealInFinder(root.certFile)
                            }
                        }
                    }
                }
            }

            Components.SettingsLabeledInput {
                title: Strings.t("certificate.key.file")
                description: "Open the private key file for this website."

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Components.AppTextField {
                        Layout.fillWidth: true
                        text: root.keyFile
                        readOnly: true
                    }

                    Components.AppButton {
                        text: "Reveal in Finder"
                        enabled: root.keyFile.length > 0
                        onClicked: {
                            if (dashboardBridge && dashboardBridge.revealInFinder) {
                                dashboardBridge.revealInFinder(root.keyFile)
                            }
                        }
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: Strings.t("enforce.tls")
                description: "Redirect HTTP traffic to HTTPS for this website."
                checked: enforceTls
                onToggled: function(nextChecked) {
                    enforceTls = nextChecked
                    refreshDirtyState()
                    if (pageRoot) {
                        pageRoot.setNodeSslEnforceTls(nextChecked)
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: Strings.t("allow.http")
                description: "Keep plain HTTP connections available for this website."
                checked: allowHttp
                onToggled: function(nextChecked) {
                    allowHttp = nextChecked
                    refreshDirtyState()
                    if (pageRoot) {
                        pageRoot.setNodeSslAllowHttp(nextChecked)
                    }
                }
            }

        }

        Item {
            Layout.fillHeight: true
        }

        footerLeft: Text {
            visible: root.currentStatusText().length > 0
            text: root.currentStatusText()
            color: root.currentStatusIsError() ? Theme.danger : Theme.success
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        footerRight: RowLayout {
            spacing: 12

            Components.AppButton {
                text: Strings.t("trust.certificate")
                visible: !!(pageRoot && pageRoot.nodeSslCertificateExists !== undefined ? pageRoot.nodeSslCertificateExists : false)
                enabled: !!dashboardBridge && !!pageRoot && String(pageRoot.nodeSslCertificatePath || "").length > 0
                onClicked: {
                    if (pageRoot && pageRoot.trustNodeProjectCertificate) {
                        pageRoot.trustNodeProjectCertificate()
                    }
                }
            }

            /*Components.AppButton {
                text: Strings.t("create.self.signed.certificate")
                enabled: !!dashboardBridge && !!pageRoot
                onClicked: {
                    if (pageRoot && pageRoot.createNodeProjectCertificate) {
                        pageRoot.createNodeProjectCertificate()
                    }
                }
            }*/

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                enabled: !!dashboardBridge && !!pageRoot && !pageRoot.nodeProjectSaveBusy
                onClicked: {
                    root.saveDomainAndSslSettings()
                }
            }
        }
    }
}
