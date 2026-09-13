import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components"
as Components
import "../../i18n"

Item {
    id: root
    property
    var siteData: ({})
    property
    var dashboardBridge
    property bool sessionIsolation: false
    property string feedbackText: ""
    property bool feedbackIsError: false

    function refreshSelectedVersion() {
        if (!dashboardBridge) {
            return
        }
        phpVersionCombo.model = dashboardBridge.phpVersions
        var currentVersion = siteData.php ? siteData.php : ""
        var currentIndex = dashboardBridge.phpVersions.indexOf(currentVersion)
        phpVersionCombo.currentIndex = currentIndex >= 0 ? currentIndex : 0
    }

    onSiteDataChanged: refreshSelectedVersion()
    onDashboardBridgeChanged: refreshSelectedVersion()
    Component.onCompleted: refreshSelectedVersion()

    Components.SettingsTabFrame {
        anchors.fill: parent


        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: Strings.t("default.php.version")
                color: Theme.text
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Label {
                    text: Strings.t("default.php.version")
                    color: Theme.text
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignVCenter
                }

                Components.AppComboBox {
                    id: phpVersionCombo
                    Layout.preferredWidth: 124
                    model: dashboardBridge ? dashboardBridge.phpVersions : []
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: "· " + Strings.t("u2022.select.the.version.according.to.your.program.requirements")
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    text: "· " + Strings.t("u2022.avoid.very.old.php.versions.unless.the.project.strictly.requires.them")
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    text: "· " + Strings.t("u2022.newer.php.releases.use.mysqli.and.pdo.mysql.by.default.for.mysql.connectivity")
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    text: "· " + Strings.t("u2022.custom.php.connection.settings.can.be.added.later.in.this.section")
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    text: "· " + Strings.t("u2022.tcp.and.unix.socket.targets.should.be.supported.here.later")
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 18

                Label {
                    text: Strings.t("session.isolation")
                    color: Theme.text
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }

                Components.AppSwitch {
                    checked: sessionIsolation
                    onToggled: sessionIsolation = checked
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: "· " + Strings.t("u2022.when.enabled.session.files.are.stored.in.a.dedicated.folder.instead.of.a.shared.path")
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    text: "· " + Strings.t("u2022.do.not.enable.this.if.the.project.stores.sessions.in.memcache.redis.or.another.shared.backend")
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }

            Item {
                Layout.fillHeight: true
            }
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
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    if (!dashboardBridge || !siteData.id) {
                        return
                    }
                    var ok = dashboardBridge.updateSitePhpVersion(siteData.id, phpVersionCombo.currentText)
                    feedbackText = dashboardBridge.lastOperationMessage
                    feedbackIsError = !ok
                }
            }
        }
    }
}
