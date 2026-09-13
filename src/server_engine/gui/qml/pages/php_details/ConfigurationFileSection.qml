import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root
    property var phpRuntime: ({})
    property var dashboardBridge
    property string feedbackText: ""
    property bool feedbackIsError: false
    property string pendingIniContent: ""
    property bool saveInProgress: false
    property bool restoreConfirmOpen: false

    Layout.fillWidth: true
    Layout.fillHeight: true

    function iniPath() {
        if (!phpRuntime || !phpRuntime.ini_dir) {
            return ""
        }
        return phpRuntime.ini_dir + "/php.ini"
    }

    function loadIniContent() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        dashboardBridge.ensurePhpIniDefaultBackup(phpRuntime.version)
        var content = dashboardBridge.phpIniContent(phpRuntime.version)
        pendingIniContent = content
        fallbackEditor.text = content
        feedbackText = ""
        feedbackIsError = false
    }

    function saveIniContent() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        saveInProgress = true
        feedbackText = "Saving php.ini..."
        feedbackIsError = false
        var ok = dashboardBridge.savePhpIni(phpRuntime.version, fallbackEditor.text)
        feedbackText = dashboardBridge.lastOperationMessage
        feedbackIsError = !ok
        saveInProgress = false
    }

    function applyEditorContent(content) {
        pendingIniContent = content
        fallbackEditor.text = content
    }

    function restoreDefaultIni() {
        if (!dashboardBridge || !phpRuntime || !phpRuntime.version) {
            return
        }
        var content = dashboardBridge.phpIniDefaultContent(phpRuntime.version)
        if (content.length === 0) {
            feedbackText = "Default php.ini backup is not available."
            feedbackIsError = true
            return
        }
        applyEditorContent(content)
        feedbackText = "Loaded default php.ini content into editor. Click Save to apply."
        feedbackIsError = false
    }

    onPhpRuntimeChanged: loadIniContent()
    Component.onCompleted: loadIniContent()

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radius
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Components.AppScrollEditor {
                    id: fallbackEditor
                    anchors.fill: parent
                    readOnly: false
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    textFormat: TextEdit.PlainText
                    fontFamily: "Menlo"
                    fontPixelSize: 12
                    textColor: Theme.text
                    contentPadding: 8
                }
            }
        }

        footerLeft: Text {
            Layout.fillWidth: true
            visible: feedbackText.length > 0
            text: feedbackText
            color: feedbackIsError ? "#b33a3a" : "#2f7d32"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 10

            Components.AppButton {
                text: Strings.t("reveal.in.finder")
                onClicked: dashboardBridge.revealInFinder(root.iniPath())
            }

            Components.AppButton {
                text: Strings.t("reload")
                onClicked: root.loadIniContent()
            }

            Components.AppButton {
                text: Strings.t("restore.default")
                onClicked: root.restoreConfirmOpen = true
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                enabled: !root.saveInProgress
                onClicked: root.saveIniContent()
            }
        }
    }

    Window {
        id: restoreConfirmDialog
        visible: root.restoreConfirmOpen
        width: 500
        height: 210
        title: Strings.t("restore.default.content")
        modality: Qt.ApplicationModal
        transientParent: root.Window.window
        flags: Qt.Dialog | Qt.WindowCloseButtonHint
        color: Theme.surface

        onVisibleChanged: {
            if (!visible) {
                root.restoreConfirmOpen = false
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Strings.t("load.default.php.ini.content.into.the.editor.this.does.not.save.to.file.until.you.click.save")
                    color: Theme.text
                    font.pixelSize: 13
                }

                Item { width: 1; height: 1 }

                Row {
                    spacing: 10

                    Components.AppButton {
                        text: Strings.t("load")
                        onClicked: {
                            root.restoreConfirmOpen = false
                            root.restoreDefaultIni()
                        }
                    }

                    Components.AppButton {
                        text: Strings.t("cancel")
                        onClicked: root.restoreConfirmOpen = false
                    }
                }
            }
        }
    }
}



