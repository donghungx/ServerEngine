import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"

Item {
    id: host
    required property var root
    readonly property var bridge: root ? root.dashboardBridge : null
    property string proxyId: ""
    property var proxyData: ({})
    property bool proxySslEnforceTls: false
    property bool proxySslAllowHttp: true
    property string proxyCertFile: ""
    property string proxyKeyFile: ""
    readonly property bool proxySslCertificateBusy: bridge ? !!bridge.proxySslCertificateBusy : false

    Window {
        id: proxyWindow
        width: 720
        height: 520
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        visible: host.root ? host.root.addProxyOpen : false
        title: ""
        color: "transparent"
        modality: Qt.WindowModal
        transientParent: host.root && host.root.Window ? host.root.Window.window : null
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.FramelessWindowHint

        property bool saving: false
        property string validationMessage: ""
        property bool validationError: false

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
                    proxyWindow.startSystemMove()
                    mouse.accepted = true
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

            Text {
                Layout.fillWidth: true
                text: host.proxyId.length > 0 ? "Modify Proxy Project" : "Add Proxy Project"
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 11

                Components.SettingsLabeledInput {
                    title: "Domain"
                    description: "The local domain people will open."
                    Components.AppTextField { id: proxyDomain; Layout.fillWidth: true; placeholderText: "app.local" }
                }
                Components.SettingsLabeledInput {
                    title: "Target"
                    description: "An HTTP address such as http://127.0.0.1:49174, or unix:/absolute/path.sock."
                    Components.AppTextField { id: proxyTarget; Layout.fillWidth: true; placeholderText: "http://127.0.0.1:49174" }
                }
                Components.SettingsLabeledInput {
                    title: "Note"
                    description: "Optional reminder about this service."
                    Components.AppTextField { id: proxyNotes; Layout.fillWidth: true; placeholderText: "Optional note" }
                }
                Components.SettingsCheckableOption {
                    id: proxySslCheckbox
                    title: "Enable SSL"
                    description: "Create a local HTTPS certificate and serve this proxy at https://your-domain."
                    checked: false
                    itemEnabled: !proxyWindow.saving && !host.proxySslCertificateBusy
                    onToggled: function(value) {
                        if (value && host.proxyId.length > 0 && bridge) {
                            var started = bridge.ensureProxySslCertificate(host.proxyId)
                            if (!started) {
                                proxySslCheckbox.checked = false
                            }
                        }
                    }
                    Layout.fillWidth: true
                }
                Text {
                    visible: host.proxySslCertificateBusy
                    text: "Creating SSL certificate..."
                    color: Theme.muted
                    font.pixelSize: 12
                    Layout.fillWidth: true
                    Layout.leftMargin: 198
                }
                Components.SettingsLabeledInput {
                    visible: proxySslCheckbox.checked && host.proxyId.length > 0
                    title: "Certificate file"
                    description: "The local HTTPS certificate used by this proxy."
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: host.proxyCertFile
                            readOnly: true
                        }
                        Components.AppButton {
                            text: "Reveal in Finder"
                            enabled: host.proxyCertFile.length > 0
                            onClicked: if (bridge && bridge.revealInFinder) bridge.revealInFinder(host.proxyCertFile)
                        }
                    }
                }
                Components.SettingsLabeledInput {
                    visible: proxySslCheckbox.checked && host.proxyId.length > 0
                    title: "Certificate key file"
                    description: "The private key used by this proxy's HTTPS certificate."
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: host.proxyKeyFile
                            readOnly: true
                        }
                        Components.AppButton {
                            text: "Reveal in Finder"
                            enabled: host.proxyKeyFile.length > 0
                            onClicked: if (bridge && bridge.revealInFinder) bridge.revealInFinder(host.proxyKeyFile)
                        }
                    }
                }
                RowLayout {
                    visible: proxySslCheckbox.checked && host.proxyId.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 198
                    spacing: 8
                    Components.StatusTextButton {
                        label: "Regenerate certificate"
                        iconSource: "../icons/lucide/rotate-cw.svg"
                        enabled: !!bridge && host.proxyId.length > 0
                        tooltip: "Create a new self-signed certificate for this proxy."
                        onClicked: {
                            var ok = bridge.regenerateProxySelfSignedCertificate(host.proxyId)
                            host.root.addSiteFeedback = bridge.lastOperationMessage
                            host.root.addSiteFeedbackError = !ok
                        }
                    }
                    Components.StatusTextButton {
                        label: "Trust certificate"
                        iconSource: "../icons/lucide/shield-check.svg"
                        enabled: !!bridge && host.proxyId.length > 0 && host.proxyCertFile.length > 0
                        tooltip: "Trust this certificate in macOS for local HTTPS development."
                        onClicked: {
                            var ok = bridge.trustProxyCertificate(host.proxyId)
                            host.root.addSiteFeedback = bridge.lastOperationMessage
                            host.root.addSiteFeedbackError = !ok
                        }
                    }
                }
                Components.SettingsCheckableOption {
                    title: "Enforce TLS"
                    description: "Redirect HTTP requests to HTTPS and require encrypted connections."
                    checked: proxySslEnforceTls
                    visible: proxySslCheckbox.checked
                    itemEnabled: !proxyWindow.saving && proxySslCheckbox.checked
                    onToggled: function(value) {
                        proxySslEnforceTls = value
                        if (value) proxySslAllowHttp = false
                    }
                    Layout.fillWidth: true
                }
                Components.SettingsCheckableOption {
                    title: "Allow HTTP"
                    description: "Keep plain HTTP connections available for this proxy."
                    checked: proxySslAllowHttp
                    visible: proxySslCheckbox.checked
                    itemEnabled: !proxyWindow.saving && proxySslCheckbox.checked && !proxySslEnforceTls
                    opacity: itemEnabled ? 1.0 : 0.45
                    onToggled: function(value) { proxySslAllowHttp = value }
                    Layout.fillWidth: true
                }
            }

            Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    visible: proxyWindow.validationMessage.length > 0 || (host.root && host.root.addSiteFeedback.length > 0)
                text: proxyWindow.validationMessage.length > 0 ? proxyWindow.validationMessage : host.root.addSiteFeedback
                color: proxyWindow.validationError || (host.root && host.root.addSiteFeedbackError) ? "#d66a6a" : Theme.accentStrong
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                Components.AppButton {
                    text: "Cancel"
                    enabled: !host.proxySslCertificateBusy
                    onClicked: proxyWindow.close()
                }
                Components.AppButton {
                    text: proxyWindow.saving ? "Saving..." : (host.proxyId.length > 0 ? "Save Changes" : "Create Proxy Project")
                    enabled: !proxyWindow.saving && !host.proxySslCertificateBusy
                    onClicked: {
                        if (!proxyWindow.validateForm()) {
                            return
                        }
                        proxyWindow.saving = true
                        var ok = bridge && host.proxyId.length > 0
                            ? bridge.updateProxy(host.proxyId, proxyDomain.text, proxyDomain.text, proxyTarget.text, proxyNotes.text, proxySslCheckbox.checked, proxySslEnforceTls, proxySslAllowHttp)
                            : bridge && bridge.createProxy(proxyDomain.text, proxyDomain.text, proxyTarget.text, proxyNotes.text, proxySslCheckbox.checked, proxySslEnforceTls, proxySslAllowHttp)
                        if (ok) {
                            host.root.addProxyOpen = false
                        } else {
                            proxyWindow.saving = false
                        }
                    }
                }
            }
            }
        }

        function clearForm() {
            proxyDomain.text = ""
            proxyTarget.text = ""
            proxyNotes.text = ""
            proxySslCheckbox.checked = false
            proxySslEnforceTls = false
            proxySslAllowHttp = true
            proxyCertFile = ""
            proxyKeyFile = ""
            validationMessage = ""
            validationError = false
        }

        function loadProxy() {
            proxyDomain.text = String(proxyData.local_domain || "")
            proxyTarget.text = String(proxyData.target || "")
            proxyNotes.text = String(proxyData.notes || "")
            proxySslCheckbox.checked = Boolean(proxyData.ssl_enabled)
            proxySslEnforceTls = Boolean(proxyData.ssl_enforce_tls)
            proxySslAllowHttp = proxyData.ssl_allow_http !== undefined ? Boolean(proxyData.ssl_allow_http) : true
            proxyCertFile = String(proxyData.ssl_certificate_path || "")
            proxyKeyFile = String(proxyData.ssl_key_path || "")
            validationMessage = ""
            validationError = false
        }

        function validateForm() {
            var domain = proxyDomain.text.trim().toLowerCase()
            var target = proxyTarget.text.trim()
            if (domain.length === 0) {
                validationMessage = "A local domain is required."
                validationError = true
                return false
            }
            if (target.length === 0) {
                validationMessage = "A target URL or Unix socket path is required."
                validationError = true
                return false
            }
            if (domain.indexOf(".") < 1 || domain.indexOf(" ") >= 0) {
                validationMessage = "Use a domain such as app.local or dashboard.test."
                validationError = true
                return false
            }
            if (!(target.indexOf("http://") === 0 || target.indexOf("https://") === 0 || target.indexOf("unix:") === 0 || target.indexOf("/") === 0)) {
                validationMessage = "Target must start with http://, https://, unix:, or /."
                validationError = true
                return false
            }
            if (host.root && host.root.domainExists && host.root.domainExists(domain)) {
                validationMessage = "That domain is already in use."
                validationError = true
                return false
            }
            validationMessage = ""
            validationError = false
            return true
        }

        onVisibleChanged: {
            if (visible) {
                saving = false
                clearForm()
                if (host.proxyId.length > 0) {
                    loadProxy()
                }
                raise()
                requestActivate()
                proxyDomain.forceActiveFocus()
            }
        }

        onClosing: {
            if (host.root) {
                host.root.addProxyOpen = false
            }
        }
    }
}
