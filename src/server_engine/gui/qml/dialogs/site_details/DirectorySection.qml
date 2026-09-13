import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var siteData: ({})
    property var dashboardBridge

    property bool antiXssEnabled: true
    property bool writeAccessLog: false
    property bool passwordAccess: false
    property string passwordAccessUser: ""
    property string passwordAccessPass: ""
    property string loadedSecuritySiteId: ""
    property string feedbackText: ""
    property bool feedbackIsError: false
    property var runningDirectoryChoices: ["/"]

    function refreshChoices() {
        if (!dashboardBridge) {
            runningDirectoryChoices = ["/"]
            runningDirectoryCombo.model = runningDirectoryChoices
            runningDirectoryCombo.currentIndex = 0
            return
        }
        runningDirectoryChoices = dashboardBridge.siteDirectoryChoices(siteDirectoryField.text.trim())
        var currentDisplay = siteData.web_root_display ? siteData.web_root_display : "/"
        if (runningDirectoryChoices.indexOf(currentDisplay) === -1) {
            runningDirectoryChoices = runningDirectoryChoices.concat([currentDisplay])
        }
        runningDirectoryCombo.model = runningDirectoryChoices
        runningDirectoryCombo.currentIndex = Math.max(0, runningDirectoryChoices.indexOf(currentDisplay))
    }

    function applySiteData() {
        siteDirectoryField.text = siteData.project_path ? siteData.project_path : ""
        if (dashboardBridge && siteData && siteData.id && loadedSecuritySiteId !== String(siteData.id)) {
            antiXssEnabled = dashboardBridge.siteOpenBasedirEnabled(String(siteData.id))
            writeAccessLog = dashboardBridge.siteWriteAccessLogEnabled(String(siteData.id))
            passwordAccess = dashboardBridge.sitePasswordAccessEnabled(String(siteData.id))
            passwordAccessUser = dashboardBridge.sitePasswordAccessUsername(String(siteData.id))
            passwordAccessPass = ""
            loadedSecuritySiteId = String(siteData.id)
        }
        refreshChoices()
    }

    function saveDirectorySettings() {
        if (!dashboardBridge || !siteData.id) {
            return
        }
        var runningRoot = runningDirectoryCombo.currentText === "/" ? "." : runningDirectoryCombo.currentText
        var ok = dashboardBridge.updateSiteDirectorySettings(
            siteData.id,
            siteDirectoryField.text.trim(),
            runningRoot
        )
        if (ok) {
            ok = dashboardBridge.saveSiteOpenBasedir(siteData.id, antiXssEnabled)
        }
        if (ok) {
            ok = dashboardBridge.saveSiteDirectorySecuritySettings(
                siteData.id,
                writeAccessLog,
                passwordAccess,
                passwordAccessUser.trim(),
                passwordAccessPass
            )
            if (ok) {
                passwordAccessPass = ""
            }
        }
        feedbackText = dashboardBridge.lastOperationMessage
        feedbackIsError = !ok
    }

    onSiteDataChanged: applySiteData()
    onDashboardBridgeChanged: applySiteData()
    Component.onCompleted: applySiteData()

    Components.SettingsTabFrame {
        anchors.fill: parent

        ColumnLayout {
            spacing: 16

        ColumnLayout {
            spacing: 8

            Components.SettingsLabeledInput {
                title: Strings.t("site.directory")
                description: Strings.t("some.programs.need.a.secondary.working.directory.inside.the.site.path")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Components.AppTextField {
                        id: siteDirectoryField
                        Layout.fillWidth: true
                        placeholderText: Strings.t("users.you.sites.example")
                        onTextChanged: refreshChoices()
                    }

                    Components.AppButton {
                        text: Strings.t("choose.path")
                        implicitWidth: 116
                        onClicked: folderDialog.open()
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: Strings.t("running.directory")
                description: Strings.t("select.the.working.directory.for.frameworks.or.apps.that.run.below.the.project.root")

                Components.AppComboBox {
                    id: runningDirectoryCombo
                    Layout.fillWidth: true
                    model: root.runningDirectoryChoices
                }
            }
        }

        ColumnLayout {
            spacing: 16

            Components.SettingsCheckableOption {
                Layout.fillWidth: true
                title: Strings.t("restrict.php.file.access.open.basedir")
                description: "Limit PHP file access to this site path and temp dirs."
                checked: antiXssEnabled
                onToggled: function(nextChecked) {
                    antiXssEnabled = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                Layout.fillWidth: true
                title: Strings.t("write.access.log")
                description: "Write Apache or Nginx access logs for this site."
                checked: writeAccessLog
                onToggled: function(nextChecked) {
                    writeAccessLog = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                Layout.fillWidth: true
                title: Strings.t("password.access")
                description: "Protect this directory with a username and password."
                checked: passwordAccess
                onToggled: function(nextChecked) {
                    passwordAccess = nextChecked
                }
            }

            Components.SettingsLabeledInput {
                visible: passwordAccess
                title: Strings.t("username")

                Components.AppTextField {
                    Layout.fillWidth: true
                    text: root.passwordAccessUser
                    placeholderText: Strings.t("admin")
                    onTextChanged: root.passwordAccessUser = text
                }
            }

            Components.SettingsLabeledInput {
                visible: passwordAccess
                title: Strings.t("password")

                Components.AppTextField {
                    Layout.fillWidth: true
                    text: root.passwordAccessPass
                    placeholderText: Strings.t("leave.blank.to.keep.existing.password")
                    echoMode: TextInput.Password
                    onTextChanged: root.passwordAccessPass = text
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
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                onClicked: root.saveDirectorySettings()
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: Strings.t("choose.site.directory")
        currentFolder: siteDirectoryField.text.trim().length > 0
            ? "file://" + encodeURI(siteDirectoryField.text.trim())
            : "file://" + encodeURI(siteData.project_path ? siteData.project_path : "/")
        onAccepted: {
            var value = selectedFolder.toString()
            if (value.indexOf("file://") === 0) {
                siteDirectoryField.text = decodeURIComponent(value.slice(7))
            } else {
                siteDirectoryField.text = value
            }
        }
    }
}
