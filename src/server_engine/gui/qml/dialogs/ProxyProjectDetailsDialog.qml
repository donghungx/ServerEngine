import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: dialog

    required property var root
    readonly property var dashboardBridge: root.dashboardBridge
    property string activeTab: "domain"
    property var proxyData: ({})
    property bool saving: false
    property string feedback: ""
    property bool feedbackError: false
    property string certFile: ""
    property string keyFile: ""
    readonly property bool sslCertificateBusy: dashboardBridge ? !!dashboardBridge.proxySslCertificateBusy : false

    width: 736
    height: 560
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    visible: root.proxyDetailsOpen
    title: String(proxyData.local_domain || "Proxy Project")
    modality: Qt.ApplicationModal
    transientParent: root.Window.window
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
    color: Theme.surface

    function loadProxy() {
        proxyDomain.text = String(proxyData.local_domain || "")
        proxyTarget.text = String(proxyData.target || "")
        proxyNotes.text = String(proxyData.notes || "")
        proxySslEnabled.checked = !!proxyData.ssl_enabled
        proxySslEnforce.checked = !!proxyData.ssl_enforce_tls
        proxySslAllowHttp.checked = proxyData.ssl_allow_http !== undefined ? !!proxyData.ssl_allow_http : true
        certFile = String(proxyData.ssl_certificate_path || "")
        keyFile = String(proxyData.ssl_key_path || "")
        feedback = ""
        feedbackError = false
    }

    function saveProxy() {
        var domain = proxyDomain.text.trim().toLowerCase()
        var target = proxyTarget.text.trim()
        if (!domain || !target) {
            feedback = "Domain and target are required."
            feedbackError = true
            return
        }
        saving = true
        var ok = dashboardBridge.updateProxy(
            String(proxyData.id || ""), domain, domain, target, proxyNotes.text,
            proxySslEnabled.checked, proxySslEnforce.checked, proxySslAllowHttp.checked
        )
        saving = false
        if (ok) {
            proxyData = dashboardBridge.proxyItems.find(function(item) { return String(item.id || "") === String(proxyData.id || "") }) || proxyData
            feedback = "Proxy project updated."
            feedbackError = false
            root.editingProxyData = proxyData
        } else {
            feedback = String(dashboardBridge.lastOperationMessage || "Unable to update proxy project.")
            feedbackError = true
        }
    }

    function refreshCertificatePaths() {
        if (!dashboardBridge || !proxyData.id) {
            return
        }
        var items = dashboardBridge.proxyItems || []
        for (var i = 0; i < items.length; i++) {
            if (String(items[i].id || "") === String(proxyData.id || "")) {
                proxyData = items[i]
                certFile = String(items[i].ssl_certificate_path || "")
                keyFile = String(items[i].ssl_key_path || "")
                break
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            activeTab = "domain"
            loadProxy()
            raise()
            requestActivate()
        }
    }

    onClosing: root.proxyDetailsOpen = false

    Connections {
        target: dashboardBridge
        function onDataChanged() { dialog.refreshCertificatePaths() }
    }

    Components.PageWindowFrame {
        moveWindow: dialog
        bodyMargins: 16

        headerContent: Item {
            anchors.fill: parent

            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                text: activeTab === "domain" ? "Domain" : Strings.t("response.log")
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                height: 56
                spacing: 6

                Components.TopIconTab {
                    label: "Domain"
                    selected: activeTab === "domain"
                    iconSource: "../icons/lucide/globe-check.svg"
                    onClicked: activeTab = "domain"
                }
                Components.TopIconTab {
                    label: Strings.t("response.log")
                    selected: activeTab === "response.log"
                    iconSource: "../icons/lucide/activity.svg"
                    onClicked: activeTab = "response.log"
                }
            }
        }

        Item {
            anchors.fill: parent
            anchors.bottomMargin: 48
            visible: activeTab === "domain"

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: domainForm.implicitHeight
                clip: true

                ColumnLayout {
                    id: domainForm
                    width: parent.width
                    spacing: 14

                    Components.SettingsLabeledInput {
                    title: "Domain"
                    description: "The local domain for this proxy project."
                    Components.AppTextField { id: proxyDomain; Layout.fillWidth: true }
                    }
                    Components.SettingsLabeledInput {
                    title: "Target"
                    description: "The HTTP service or Unix socket receiving proxied requests."
                    Components.AppTextField { id: proxyTarget; Layout.fillWidth: true }
                    }
                    Components.SettingsLabeledInput {
                    title: "Note"
                    description: "Optional reminder about this proxy project."
                    Components.AppTextField { id: proxyNotes; Layout.fillWidth: true }
                    }
                    Components.SettingsCheckableOption {
                    id: proxySslEnabled
                    title: "Enable SSL"
                    description: "Serve this proxy over local HTTPS."
                    checked: false
                    itemEnabled: !saving && !sslCertificateBusy
                    onToggled: function(value) {
                        if (value && dashboardBridge && proxyData.id) {
                            var started = dashboardBridge.ensureProxySslCertificate(String(proxyData.id))
                            if (!started) {
                                proxySslEnabled.checked = false
                            }
                        }
                    }
                    Layout.fillWidth: true
                    Text {
                        visible: sslCertificateBusy
                        text: "Creating SSL certificate..."
                        color: Theme.muted
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        Layout.leftMargin: 198
                    }
                    }

                    Components.SettingsLabeledInput {
                    visible: proxySslEnabled.checked
                    title: "Certificate file"
                    description: "Open the certificate file for this proxy."
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Components.AppTextField { Layout.fillWidth: true; text: certFile; readOnly: true }
                        Components.AppButton {
                            text: "Reveal in Finder"
                            enabled: certFile.length > 0
                            onClicked: if (dashboardBridge) dashboardBridge.revealInFinder(certFile)
                        }
                    }
                    }

                    Components.SettingsLabeledInput {
                    visible: proxySslEnabled.checked
                    title: "Certificate key file"
                    description: "Open the private key file for this proxy."
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Components.AppTextField { Layout.fillWidth: true; text: keyFile; readOnly: true }
                        Components.AppButton {
                            text: "Reveal in Finder"
                            enabled: keyFile.length > 0
                            onClicked: if (dashboardBridge) dashboardBridge.revealInFinder(keyFile)
                        }
                    }
                    }

                    RowLayout {
                    visible: proxySslEnabled.checked
                    Layout.fillWidth: true
                    Layout.leftMargin: 198 + 16
                    spacing: 8
                    Components.StatusTextButton {
                        label: "Regenerate certificate"
                        iconSource: "../icons/lucide/rotate-cw.svg"
                        enabled: !!dashboardBridge && !!proxyData.id && !sslCertificateBusy
                        tooltip: "Create a new self-signed certificate for this proxy."
                        onClicked: {
                            var ok = dashboardBridge.regenerateProxySelfSignedCertificate(String(proxyData.id))
                            feedback = dashboardBridge.lastOperationMessage
                            feedbackError = !ok
                            if (ok) refreshCertificatePaths()
                        }
                    }
                    Components.StatusTextButton {
                        label: "Trust certificate"
                        iconSource: "../icons/lucide/shield-check.svg"
                        enabled: !!dashboardBridge && !!proxyData.id && certFile.length > 0
                        tooltip: "Trust this certificate in macOS for local HTTPS development."
                        onClicked: {
                            var ok = dashboardBridge.trustProxyCertificate(String(proxyData.id))
                            feedback = dashboardBridge.lastOperationMessage
                            feedbackError = !ok
                        }
                    }
                    }

                    Components.SettingsCheckableOption {
                    id: proxySslEnforce
                    title: "Enforce TLS"
                    description: "Redirect HTTP requests to HTTPS."
                    checked: false
                    visible: proxySslEnabled.checked
                    itemEnabled: proxySslEnabled.checked && !saving
                    Layout.fillWidth: true
                    onToggled: function(value) { if (value) proxySslAllowHttp.checked = false }
                    }
                    Components.SettingsCheckableOption {
                    id: proxySslAllowHttp
                    title: "Allow HTTP"
                    description: "Keep plain HTTP connections available."
                    checked: true
                    visible: proxySslEnabled.checked
                    itemEnabled: proxySslEnabled.checked && !proxySslEnforce.checked && !saving
                    Layout.fillWidth: true
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }

        Components.FileLogSection {
            anchors.fill: parent
            anchors.bottomMargin: 48
            visible: activeTab === "response.log"
            title: Strings.t("response.log")
            description: "Read the web server access log for this proxy project."
            emptyText: "No proxy response log yet."
            logPathProvider: function() {
                return dashboardBridge.proxyProjectResponseLogPath(String(proxyData.id || ""))
            }
            logContentProvider: function(lines, tailMode) {
                return dashboardBridge.proxyProjectResponseLogContent(String(proxyData.id || ""), lines)
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 32
            spacing: 8

            Label {
                Layout.fillWidth: true
                visible: feedback.length > 0
                text: feedback
                color: feedbackError ? Theme.dialogFeedbackErrorText : Theme.dialogFeedbackSuccessText
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true; visible: feedback.length === 0 }

            Components.AppButton {
                visible: activeTab === "domain"
                text: "Close"
                onClicked: root.proxyDetailsOpen = false
            }
            Components.AppButton {
                visible: activeTab === "domain"
                text: saving ? "Saving..." : "Save Changes"
                highlighted: true
                enabled: !saving && !sslCertificateBusy
                onClicked: saveProxy()
            }
        }
    }
}
