import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: sslSection
    property var siteData: ({})
    property var dashboardBridge
    property bool sslEnabled: siteData.ssl === "60 Days"
    property bool sslEnabledDirty: false
    property bool enforceTls: false
    property bool allowHttp: false
    property bool sslOptionsDirty: false
    property string certFile: siteData.ssl_certificate_path ? siteData.ssl_certificate_path : ""
    property string keyFile: siteData.ssl_key_path ? siteData.ssl_key_path : ""
    property string chainFile: ""
    property string feedbackText: ""
    property bool feedbackIsError: false

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
        console.log(
            "[SslSection] refreshDirtyState site_id=",
            siteData && siteData.id ? String(siteData.id) : "",
            "ssl_enabled_current=",
            String(sslEnabled),
            "ssl_enabled_saved=",
            String(normalizedSiteSslEnabled()),
            "enforce_tls_current=",
            String(enforceTls),
            "enforce_tls_saved=",
            String(normalizedSiteEnforceTls()),
            "allow_http_current=",
            String(allowHttp),
            "allow_http_saved=",
            String(normalizedSiteAllowHttp())
        )
        sslEnabledDirty = sslEnabled !== normalizedSiteSslEnabled()
        sslOptionsDirty = enforceTls !== normalizedSiteEnforceTls() || allowHttp !== normalizedSiteAllowHttp()
    }

    onSiteDataChanged: {
        console.log(
            "[SslSection] onSiteDataChanged site_id=",
            siteData && siteData.id ? String(siteData.id) : "",
            "ssl_enabled=",
            siteData && siteData.ssl_enabled !== undefined ? String(siteData.ssl_enabled) : "undefined",
            "ssl_enforce_tls=",
            siteData && siteData.ssl_enforce_tls !== undefined ? String(siteData.ssl_enforce_tls) : "undefined",
            "ssl_allow_http=",
            siteData && siteData.ssl_allow_http !== undefined ? String(siteData.ssl_allow_http) : "undefined",
            "cert=",
            siteData && siteData.ssl_certificate_path ? String(siteData.ssl_certificate_path) : "",
            "key=",
            siteData && siteData.ssl_key_path ? String(siteData.ssl_key_path) : ""
        )
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

    component FileRow: Item {
        required property string label
        required property string value
        property string note: ""

        implicitWidth: parent ? parent.width : 300
        implicitHeight: 72

        RowLayout {
            anchors.fill: parent
            spacing: 14

            Label {
                text: parent.parent.label
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 170
                Layout.alignment: Qt.AlignTop
                wrapMode: Text.WordWrap
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                text: parent.parent.value
                readOnly: true
                wrapMode: TextEdit.WrapAnywhere
                textFormat: TextEdit.PlainText
                fontPixelSize: 12
                textColor: Theme.text
                selectByMouse: true
                persistentSelection: true
                contentPadding: 8
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Components.AppButton {
                    text: Strings.t("open")
                    implicitWidth: 70
                    enabled: parent.parent.parent.value.length > 0
                    onClicked: Qt.openUrlExternally(sslSection.fileUrl(parent.parent.parent.value))
                }
            }
        }
    }

    component OptionToggleRow: Item {
        required property string label
        property bool checked: false
        signal toggled(bool checked)

        implicitWidth: parent ? parent.width : 300
        implicitHeight: 34

        RowLayout {
            anchors.fill: parent
            spacing: 12

            Components.AppSwitch {
                id: optionToggle
                checked: parent.parent.checked
                onToggled: function(nextChecked) {
                    console.log(
                        "[SslSection] option toggle changed label=",
                        String(parent.parent.parent.label),
                        "site_id=",
                        siteData && siteData.id ? String(siteData.id) : "",
                        "nextChecked=",
                        String(nextChecked)
                    )
                    parent.parent.checked = nextChecked
                    parent.parent.toggled(nextChecked)
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: optionLabel.implicitHeight

                Label {
                    id: optionLabel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.parent.label
                    color: Theme.text
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function() {
                        var nextChecked = !optionToggle.checked
                        console.log(
                            "[SslSection] option label clicked label=",
                            String(parent.parent.parent.label),
                            "site_id=",
                            siteData && siteData.id ? String(siteData.id) : "",
                            "nextChecked=",
                            String(nextChecked)
                        )
                        optionToggle.checked = nextChecked
                        parent.parent.checked = nextChecked
                        parent.parent.toggled(nextChecked)
                    }
                }
            }

        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent

        ColumnLayout {
            spacing: 16

            Label {
                text: "SSL & HTTPS"
                color: Theme.text
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: "Create or trust the certificate here, then choose whether this site should force HTTPS and whether insecure HTTP should still be allowed."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Components.AppSwitch {
                    checked: sslEnabled
                    onToggled: function(nextChecked) {
                        console.log(
                            "[SslSection] ssl toggle site_id=",
                            siteData && siteData.id ? String(siteData.id) : "",
                            "nextChecked=",
                            String(nextChecked)
                        )
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
                                checked = !nextChecked
                                sslEnabled = !nextChecked
                                refreshDirtyState()
                                return
                            }
                        }
                    }
                }

                Label {
                    text: Strings.t("enable.ssl")
                    color: Theme.text
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            FileRow {
                Layout.fillWidth: true
                label: Strings.t("certificate.file")
                value: certFile
            }

            FileRow {
                Layout.fillWidth: true
                label: Strings.t("certificate.key.file")
                value: keyFile
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                OptionToggleRow {
                    Layout.fillWidth: true
                    label: Strings.t("enforce.tls.encryption.do.not.allow.insecure.methods")
                    checked: enforceTls
                    onToggled: function(nextChecked) {
                        console.log(
                            "[SslSection] enforceTls toggled site_id=",
                            siteData && siteData.id ? String(siteData.id) : "",
                            "nextChecked=",
                            String(nextChecked),
                            "previous=",
                            String(enforceTls)
                        )
                        enforceTls = nextChecked
                        refreshDirtyState()
                    }
                }

                OptionToggleRow {
                    Layout.fillWidth: true
                    label: Strings.t("allow.access.to.this.site.via.insecure.http.connections")
                    checked: allowHttp
                    onToggled: function(nextChecked) {
                        console.log(
                            "[SslSection] allowHttp toggled site_id=",
                            siteData && siteData.id ? String(siteData.id) : "",
                            "nextChecked=",
                            String(nextChecked),
                            "previous=",
                            String(allowHttp)
                        )
                        allowHttp = nextChecked
                        refreshDirtyState()
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        footerLeft: Text {
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackIsError ? Theme.danger : Theme.success
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        footerRight: RowLayout {
            spacing: 12

            Components.AppButton {
                text: Strings.t("trust.certificate")
                enabled: !!dashboardBridge && !!siteData.id && certFile.length > 0
                onClicked: {
                    var ok = dashboardBridge.trustSiteCertificate(siteData.id)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackIsError = !ok
                }
            }

            Components.AppButton {
                text: Strings.t("create.self.signed.certificate")
                enabled: !!dashboardBridge && !!siteData.id
                onClicked: {
                    console.log(
                        "[SslSection] create certificate clicked site_id=",
                        siteData && siteData.id ? String(siteData.id) : ""
                    )
                    var ok = dashboardBridge.createSiteSelfSignedCertificate(siteData.id)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackIsError = !ok
                    if (ok) {
                        sslEnabled = true
                        refreshDirtyState()
                    }
                }
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                enabled: true
                onClicked: {
                    if (!dashboardBridge || !siteData.id) {
                        feedbackText = "Site is not loaded."
                        feedbackIsError = true
                        return
                    }
                    var nextSslEnabled = sslEnabled
                    var nextEnforceTls = enforceTls
                    var nextAllowHttp = allowHttp
                    console.log(
                        "[SslSection] save clicked site_id=",
                        String(siteData.id),
                        "ssl_enabled=",
                        String(nextSslEnabled),
                        "ssl_enforce_tls=",
                        String(nextEnforceTls),
                        "ssl_allow_http=",
                        String(nextAllowHttp)
                    )
                    var ok = dashboardBridge.updateSiteSslSettings(siteData.id, nextSslEnabled, nextEnforceTls, nextAllowHttp)
                    console.log(
                        "[SslSection] save result site_id=",
                        siteData && siteData.id ? String(siteData.id) : "",
                        "ok=",
                        String(ok),
                        "message=",
                        dashboardBridge ? String(dashboardBridge.lastOperationMessage) : ""
                    )
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackIsError = !ok
                    if (ok) {
                        sslEnabledDirty = false
                        sslOptionsDirty = false
                        sslEnabled = nextSslEnabled
                        enforceTls = nextEnforceTls
                        allowHttp = nextAllowHttp
                        siteData.ssl_enabled = nextSslEnabled
                        siteData.ssl_enforce_tls = nextEnforceTls
                        siteData.ssl_allow_http = nextAllowHttp
                        siteData.ssl = nextSslEnabled ? "60 Days" : "Not Set"
                    }
                }
            }
        }
    }
}
