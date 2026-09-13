import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root
    property var siteData: ({})
    property var dashboardBridge
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

        var currentSiteId = root.siteData && root.siteData.id ? String(root.siteData.id) : ""
        var websites = dashboardBridge && dashboardBridge.websiteItems ? dashboardBridge.websiteItems : []
        for (var s = 0; s < websites.length; s++) {
            var site = websites[s]
            if (String(site.id || "") === currentSiteId) {
                continue
            }
            var domains = site.domains || []
            for (var d = 0; d < domains.length; d++) {
                if (normalizedDomain(domains[d]) === value) {
                    return "Domain already used by another website."
                }
            }
        }

        var nodeProjects = dashboardBridge && dashboardBridge.nodeProjectItems ? dashboardBridge.nodeProjectItems : []
        for (var p = 0; p < nodeProjects.length; p++) {
            if (normalizedDomain(nodeProjects[p].domain) === value) {
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
        return root.feedbackText
    }

    function currentStatusIsError() {
        var conflict = hasConflict(root.domainDraft.length > 0 ? root.domainDraft[0] : "", 0)
        if (conflict.length > 0) {
            return true
        }
        return root.feedbackIsError
    }

    function normalizedSiteSslEnabled() {
        return !!siteData.ssl_enabled || siteData.ssl === "60 Days"
    }

    function normalizedSiteEnforceTls() {
        return !!siteData.ssl_enforce_tls
    }

    function normalizedSiteAllowHttp() {
        return siteData.ssl_allow_http !== undefined ? !!siteData.ssl_allow_http : true
    }

    function refreshDirtyState() {
        sslEnabledDirty = sslEnabled !== normalizedSiteSslEnabled()
        sslOptionsDirty = enforceTls !== normalizedSiteEnforceTls() || allowHttp !== normalizedSiteAllowHttp()
    }

    function syncFromSite() {
        var incoming = []
        if (root.siteData && root.siteData.domains && root.siteData.domains.length > 0) {
            incoming = [root.siteData.domains[0]]
        } else if (root.siteData && root.siteData.primary_domain) {
            incoming = [root.siteData.primary_domain]
        } else if (root.siteData && root.siteData.local_domain) {
            incoming = [root.siteData.local_domain]
        } else if (root.siteData && root.siteData.name) {
            incoming = [root.siteData.name]
        }
        if (incoming.length === 0) {
            incoming = [""]
        }
        root.domainDraft = incoming
        sslEnabled = normalizedSiteSslEnabled()
        enforceTls = normalizedSiteEnforceTls()
        allowHttp = normalizedSiteAllowHttp()
        sslEnabledDirty = false
        sslOptionsDirty = false
        certFile = siteData.ssl_certificate_path ? siteData.ssl_certificate_path : ""
        keyFile = siteData.ssl_key_path ? siteData.ssl_key_path : ""
    }

    function fileUrl(path) {
        if (!path || path.length === 0) {
            return ""
        }
        return "file://" + path
    }

    function saveSslSettings() {
        if (!dashboardBridge || !siteData.id) {
            return
        }
        var ok = dashboardBridge.updateSiteSslSettings(siteData.id, sslEnabled, enforceTls, allowHttp)
        feedbackText = dashboardBridge.lastOperationMessage
        feedbackIsError = !ok
        if (ok) {
            sslEnabledDirty = false
            sslOptionsDirty = false
            siteData.ssl_enabled = sslEnabled
            siteData.ssl_enforce_tls = enforceTls
            siteData.ssl_allow_http = allowHttp
            siteData.ssl = sslEnabled ? "60 Days" : "Not Set"
        }
    }

    function saveDomainAndSslSettings() {
        if (!dashboardBridge || !siteData.id) {
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
        var cleaned = [value]
        var ok = root.dashboardBridge.updateSiteDomains(root.siteData.id, cleaned)
        if (ok) {
            ok = root.dashboardBridge.updateSiteSslSettings(root.siteData.id, sslEnabled, enforceTls, allowHttp)
        }
        root.feedbackText = root.dashboardBridge.lastOperationMessage
        root.feedbackIsError = !ok
        if (ok) {
            root.siteData.primary_domain = cleaned[0]
            root.siteData.name = cleaned[0]
            root.siteData.local_domain = cleaned[0]
            root.siteData.domains = cleaned
            root.domainDraft = cleaned
            root.siteData.ssl_enabled = sslEnabled
            root.siteData.ssl_enforce_tls = enforceTls
            root.siteData.ssl_allow_http = allowHttp
            root.siteData.ssl = sslEnabled ? "60 Days" : "Not Set"
            sslEnabledDirty = false
            sslOptionsDirty = false
        }
    }

    onSiteDataChanged: syncFromSite()
    Component.onCompleted: syncFromSite()

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
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: Strings.t("enable.ssl")
                description: "Create a local HTTPS certificate for this site."
                checked: sslEnabled
                onToggled: function(nextChecked) {
                    sslEnabled = nextChecked
                    refreshDirtyState()
                    if (!dashboardBridge || !siteData.id) {
                        return
                    }
                    if (nextChecked) {
                        var certOk = dashboardBridge.createSiteSelfSignedCertificate(siteData.id)
                        feedbackText = dashboardBridge.lastOperationMessage
                        feedbackIsError = !certOk
                        if (!certOk) {
                            sslEnabled = !nextChecked
                            refreshDirtyState()
                            return
                        }
                        certFile = siteData.ssl_certificate_path ? siteData.ssl_certificate_path : certFile
                        keyFile = siteData.ssl_key_path ? siteData.ssl_key_path : keyFile
                    }
                }
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
                }
            }

            Components.SettingsCheckableOption {
                title: Strings.t("allow.http")
                description: "Keep plain HTTP connections available for this website."
                checked: allowHttp
                onToggled: function(nextChecked) {
                    allowHttp = nextChecked
                    refreshDirtyState()
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
                enabled: !!root.dashboardBridge && !!root.siteData.id && root.certFile.length > 0
                onClicked: {
                    var ok = root.dashboardBridge.trustSiteCertificate(root.siteData.id)
                    root.feedbackText = root.dashboardBridge.lastOperationMessage
                    root.feedbackIsError = !ok
                }
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                enabled: !!root.dashboardBridge && !!root.siteData.id
                onClicked: root.saveDomainAndSslSettings()
            }

        }
    }
}
