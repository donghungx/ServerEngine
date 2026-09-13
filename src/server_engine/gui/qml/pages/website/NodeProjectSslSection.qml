import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root

    required property var pageRoot
    required property var dashboardBridge

    function fileUrl(path) {
        var value = String(path || "")
        if (value.length === 0) {
            return ""
        }
        return "file://" + value
    }

    component FileRow: Item {
        required property string label
        required property string value

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
                    onClicked: Qt.openUrlExternally(root.fileUrl(parent.parent.parent.value))
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
                text: "Create or trust the certificate here, then choose whether this Node project should force HTTPS and whether insecure HTTP should still be allowed."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: String(pageRoot && pageRoot.addNodeProjectFeedback ? pageRoot.addNodeProjectFeedback : "").length > 0
                text: String(pageRoot && pageRoot.addNodeProjectFeedback ? pageRoot.addNodeProjectFeedback : "")
                color: pageRoot && pageRoot.addNodeProjectFeedbackError ? "#b33a3a" : "#2f7d32"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Components.AppSwitch {
                    checked: !!(pageRoot && pageRoot.nodeSslEnabled !== undefined ? pageRoot.nodeSslEnabled : false)
                    onToggled: function(nextChecked) {
                        if (pageRoot) {
                            pageRoot.setNodeSslEnabled(nextChecked)
                            if (nextChecked && !(pageRoot.nodeSslCertificateExists !== undefined ? pageRoot.nodeSslCertificateExists : false)) {
                                pageRoot.createNodeProjectCertificate()
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
                visible: !!(pageRoot && pageRoot.nodeSslCertificateExists !== undefined ? pageRoot.nodeSslCertificateExists : false)
                label: Strings.t("certificate.file")
                value: String(pageRoot && pageRoot.nodeSslCertificatePath ? pageRoot.nodeSslCertificatePath : "")
            }

            FileRow {
                Layout.fillWidth: true
                visible: !!(pageRoot && pageRoot.nodeSslCertificateExists !== undefined ? pageRoot.nodeSslCertificateExists : false)
                label: Strings.t("certificate.key.file")
                value: String(pageRoot && pageRoot.nodeSslKeyPath ? pageRoot.nodeSslKeyPath : "")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                OptionToggleRow {
                    Layout.fillWidth: true
                    label: Strings.t("enforce.tls.encryption.do.not.allow.insecure.methods")
                    checked: !!(pageRoot && pageRoot.nodeSslEnforceTls !== undefined ? pageRoot.nodeSslEnforceTls : false)
                    onToggled: function(nextChecked) {
                        if (pageRoot) {
                            pageRoot.setNodeSslEnforceTls(nextChecked)
                        }
                    }
                }

                OptionToggleRow {
                    Layout.fillWidth: true
                    label: Strings.t("allow.access.to.this.site.via.insecure.http.connections")
                    checked: pageRoot && pageRoot.nodeSslAllowHttp !== undefined ? !!pageRoot.nodeSslAllowHttp : true
                    onToggled: function(nextChecked) {
                        if (pageRoot) {
                            pageRoot.setNodeSslAllowHttp(nextChecked)
                        }
                    }
                }
            }
        }

        footerRight: RowLayout {
            spacing: 12

            Components.AppButton {
                text: Strings.t("trust.certificate")
                visible: !!(pageRoot && pageRoot.nodeSslCertificateExists !== undefined ? pageRoot.nodeSslCertificateExists : false)
                enabled: !!dashboardBridge && !!pageRoot && String(pageRoot.nodeSslCertificatePath || "").length > 0
                onClicked: {
                    if (pageRoot) {
                        pageRoot.trustNodeProjectCertificate()
                    }
                }
            }

            Components.AppButton {
                text: Strings.t("create.self.signed.certificate")
                enabled: !!dashboardBridge && !!pageRoot
                onClicked: {
                    if (pageRoot) {
                        pageRoot.createNodeProjectCertificate()
                    }
                }
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                enabled: !!dashboardBridge && !!pageRoot && !dashboardBridge.nodeProjectSaveBusy
                onClicked: {
                    if (pageRoot) {
                        pageRoot.saveNodeProjectSsl()
                    }
                }
            }
        }
    }
}


