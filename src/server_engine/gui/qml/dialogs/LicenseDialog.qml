import QtQuick
import QtQuick.Layouts
import QtQml
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: licenseDialog

    required property var window
    required property var bridge

    property bool activationForm: false
    property bool trialMode: false
    property bool actionBusy: false
    property var statusData: ({})
    property string activationFeedbackText: ""
    property bool activationFeedbackError: false
    property string trialFeedbackText: ""
    property bool trialFeedbackError: false

    visible: window.licenseDialogOpen
    width: 560
    height: 320
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("app.license.title")
    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: window
    flags: Qt.Dialog | Qt.WindowCloseButtonHint

    function refreshStatus() {
        statusData = bridge ? bridge.licenseStatus() : ({})
        activationFeedbackText = String(statusData.message || "")
        activationFeedbackError = !Boolean(statusData.valid)
        trialFeedbackText = ""
        trialFeedbackError = false
    }

    function humanDate(value) {
        var text = String(value || "")
        if (text.length === 0) {
            return ""
        }
        var date = new Date(text)
        if (isNaN(date.getTime())) {
            return text
        }
        return date.toLocaleDateString(Qt.locale(), Locale.LongFormat)
    }

    function currentSummary() {
        var status = String(statusData.status || "")
        if (status === "active") {
            return Strings.t("license.summary.active").replace("%1", String(statusData.licensedTo || "Licensed User"))
        }
        if (status === "trial") {
            return Strings.t("license.summary.trial")
        }
        if (status === "development") {
            return Strings.t("license.summary.development")
        }
        return Strings.t("license.summary.required")
    }

    function currentDetail() {
        var status = String(statusData.status || "")
        var expiresAt = String(statusData.expiresAt || "")
        if (status === "trial" && expiresAt.length > 0) {
            return Strings.t("license.detail.trial")
                .replace("%1", humanDate(expiresAt))
                .replace("%2", Number(statusData.daysRemaining || 0))
        }
        if (expiresAt.length > 0) {
            return Strings.t("license.detail.active").replace("%1", humanDate(expiresAt))
        }
        if (status === "development") {
            return Strings.t("license.detail.development")
        }
        if (Boolean(statusData.valid)) {
            return Strings.t("license.detail.valid")
        }
        return String(statusData.message || Strings.t("license.detail.default"))
    }

    function showCurrentStatus() {
        var status = String(statusData.status || "")
        return !activationForm && Boolean(statusData.valid) && (status === "active" || status === "trial")
    }

    function closeWithResult(accepted) {
        window.licenseDialogOpen = false
        window.licenseDialogFinished(Boolean(accepted))
    }

    function runAction() {
        if (actionBusy) {
            return
        }
        actionBusy = true
        var usingTrial = trialMode
        if (usingTrial) {
            trialFeedbackText = Strings.t("license.processing")
            trialFeedbackError = false
        } else {
            activationFeedbackText = Strings.t("license.processing")
            activationFeedbackError = false
        }
        var result = usingTrial ? bridge.startLicenseTrial() : bridge.activateLicense(activationCodeInput.text)
        actionBusy = false
        statusData = result
        if (usingTrial) {
            trialFeedbackText = String(result.message || "")
            trialFeedbackError = !Boolean(result.valid)
        } else {
            activationFeedbackText = String(result.message || "")
            activationFeedbackError = !Boolean(result.valid)
        }
        if (Boolean(result.valid)) {
            activationForm = false
            activationCodeInput.text = ""
        }
    }

    onVisibleChanged: {
        if (visible) {
            activationForm = false
            trialMode = false
            actionBusy = false
            activationCodeInput.text = ""
            activationFeedbackText = ""
            activationFeedbackError = false
            trialFeedbackText = ""
            trialFeedbackError = false
            refreshStatus()
        } else if (window.licenseDialogOpen) {
            closeWithResult(false)
        }
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: Strings.t("app.license.title")
        moveWindow: licenseDialog

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: Strings.t("app.title")
                color: Theme.text
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
                font.pixelSize: 22
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                visible: licenseDialog.showCurrentStatus()

                Text {
                    Layout.fillWidth: true
                    text: licenseDialog.currentSummary()
                    color: Theme.text
                    font.weight: Font.Normal
                    wrapMode: Text.WordWrap
                    font.pixelSize: 15
                }

                Text {
                    Layout.fillWidth: true
                    text: licenseDialog.currentDetail()
                    color: Theme.text
                    font.weight: Font.Normal
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: String(statusData.status || "") === "trial"
                        ? Strings.t("activate.a.license.before.the.trial.ends.to.keep.using.server.engine")
                        : (Boolean(statusData.enforced)
                            ? Strings.t("server.engine.license.is.active")
                            : Strings.t("for.local.development.use.only"))
                    color: Theme.text
                    font.weight: Font.Normal
                    wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                visible: !licenseDialog.showCurrentStatus()

                Row {
                    spacing: 20

                    Components.AppRadioButton {
                        text: Strings.t("license.action.activate")
                        checked: !licenseDialog.trialMode
                        onClicked: licenseDialog.trialMode = false
                    }

                    Components.AppRadioButton {
                        text: Strings.t("license.action.trial")
                        checked: licenseDialog.trialMode
                        onClicked: licenseDialog.trialMode = true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Strings.t("license.trial.notice")
                    visible: licenseDialog.trialMode
                    color: Theme.text
                    font.weight: Font.Normal
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: Strings.t("activation.code")
                    visible: !licenseDialog.trialMode
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.Normal
                }

                Components.AppTextField {
                    id: activationCodeInput
                    Layout.fillWidth: true
                    visible: !licenseDialog.trialMode
                    placeholderText: Strings.t("d8a48430.9804.4ae8.91f2.d5ec16fa8a6a")
                    enabled: !actionBusy
                    selectByMouse: true
                }

                Text {
                    Layout.fillWidth: true
                    text: activationFeedbackText
                    color: activationFeedbackError ? "#bb4d4d" : Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    wrapMode: Text.WordWrap
                    visible: !licenseDialog.trialMode && text.length > 0
                }

                Text {
                    Layout.fillWidth: true
                    text: trialFeedbackText
                    color: trialFeedbackError ? "#bb4d4d" : Theme.muted
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    wrapMode: Text.WordWrap
                    visible: licenseDialog.trialMode && text.length > 0
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }


        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("activate.new.license")
                enabled: !actionBusy
                highlighted: true
                onClicked: licenseDialog.activationForm = true
                visible: !licenseDialog.activationForm && licenseDialog.showCurrentStatus()
            }

            Components.AppButton {
                text: Strings.t("remove.license")
                visible: String(statusData.status || "") === "active"
                enabled: !actionBusy
                onClicked: {
                    statusData = bridge.removeActiveLicense()
                    activationFeedbackText = String(statusData.message || "")
                    activationFeedbackError = !Boolean(statusData.valid)
                    trialFeedbackText = ""
                    trialFeedbackError = false
                }
            }

            Components.AppButton {
                text: Strings.t("activate")
                visible: !licenseDialog.showCurrentStatus() && !licenseDialog.trialMode
                enabled: !actionBusy && activationCodeInput.text.trim().length > 0
                highlighted: true
                onClicked: licenseDialog.runAction()
            }

            Components.AppButton {
                text: Strings.t("start.trial")
                visible: !licenseDialog.showCurrentStatus() && licenseDialog.trialMode
                enabled: !actionBusy
                highlighted: true
                onClicked: licenseDialog.runAction()
            }

            Components.AppButton {
                text: licenseDialog.showCurrentStatus()
                    ? Strings.t("close")
                    : (window.licenseDialogStartupEnforced ? Strings.t("exit") : Strings.t("close"))
                enabled: !actionBusy
                onClicked: licenseDialog.closeWithResult(licenseDialog.showCurrentStatus())
            }
        }
    }
}
