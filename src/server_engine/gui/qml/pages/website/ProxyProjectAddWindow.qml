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

    Window {
        id: proxyWindow
        width: 800
        height: 450
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        visible: host.root ? host.root.addProxyOpen : false
        title: host.proxyId.length > 0 ? "Modify Proxy Project" : "Add Proxy Project"
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
        modality: Qt.ApplicationModal
        color: Theme.surface

        property bool saving: false
        property string validationMessage: ""
        property bool validationError: false

        function clearForm() {
            proxyDomain.text = ""
            proxyTarget.text = ""
            proxyNotes.text = ""
            proxySslCheckbox.checked = false
            validationMessage = ""
            validationError = false
        }

        function loadProxy() {
            proxyDomain.text = String(proxyData.local_domain || "")
            proxyTarget.text = String(proxyData.target || "")
            proxyNotes.text = String(proxyData.notes || "")
            proxySslCheckbox.checked = Boolean(proxyData.ssl_enabled)
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
                proxyDomain.forceActiveFocus()
            }
        }

        onClosing: {
            if (host.root) {
                host.root.addProxyOpen = false
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    text: host.proxyId.length > 0 ? "Modify Proxy Project" : "Add Proxy Project"
                    color: Theme.text
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: "Expose a Docker, Next.js, React, or any local service through a friendly domain. Server Engine forwards traffic; it does not start the target application."
                    color: Theme.muted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
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
                    itemEnabled: !proxyWindow.saving
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                Components.AppButton {
                    text: "Cancel"
                    onClicked: proxyWindow.close()
                }
                Components.AppButton {
                    text: proxyWindow.saving ? "Saving..." : (host.proxyId.length > 0 ? "Save Changes" : "Create Proxy Project")
                    enabled: !proxyWindow.saving
                    onClicked: {
                        if (!proxyWindow.validateForm()) {
                            return
                        }
                        proxyWindow.saving = true
                        var ok = bridge && host.proxyId.length > 0
                            ? bridge.updateProxy(host.proxyId, proxyDomain.text, proxyDomain.text, proxyTarget.text, proxyNotes.text, proxySslCheckbox.checked)
                            : bridge && bridge.createProxy(proxyDomain.text, proxyDomain.text, proxyTarget.text, proxyNotes.text, proxySslCheckbox.checked)
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
}
