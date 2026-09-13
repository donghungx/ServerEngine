import QtQuick
import QtQuick.Controls
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: nodeInstallDialog
    required property var window
    required property var bridge
    visible: window.nodeInstallDialogOpen
    width: 520
    height: 520
    title: Strings.t("install.node.runtime")
    color: Theme.surface
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowCloseButtonHint
    property bool installStarted: false

    onVisibleChanged: {
        if (!visible) {
            window.nodeInstallDialogOpen = false
            installStarted = false
        }
    }

    Connections {
        target: nodeInstallDialog.bridge ? nodeInstallDialog.bridge : null
        function onAppSettingsFeedbackChanged() {
            if (nodeInstallDialog.installStarted
                    && !bridge.nodeInstallBusy
                    && !bridge.appSettingsError
                    && bridge.nodeInstallProgress === 100) {
                window.nodeInstallDialogOpen = false
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                text: Strings.t("install.node.runtime")
                color: Theme.text
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }

            Text {
                text: Strings.t("choose.a.major.version.the.installer.will.fetch.the.latest.patch.release.for.that.major")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Components.AppComboBox {
                id: nodeMajorCombo
                width: 220
                model: ["16", "17", "18", "19", "20", "21", "22", "23", "24"]
                currentIndex: 4
                enabled: !bridge.nodeInstallBusy
            }

            ProgressBar {
                visible: nodeInstallDialog.installStarted
                width: parent.width
                from: 0
                to: 100
                value: bridge.nodeInstallProgress
                indeterminate: bridge.nodeInstallBusy && bridge.nodeInstallProgress <= 5
            }

            Rectangle {
                visible: nodeInstallDialog.installStarted
                width: parent.width
                height: 220
                radius: Theme.radius
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: 1

                Components.AppScrollEditor {
                    anchors.fill: parent
                    anchors.margins: 10
                    text: bridge.nodeInstallLog
                    readOnly: true
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    selectByMouse: true
                    fontFamily: "Menlo"
                    fontPixelSize: 12
                }
            }

            Row {
                spacing: 6

                Components.AppButton {
                    text: bridge.nodeInstallBusy
                        ? Strings.t("installing")
                        : Strings.t("install")

                    highlighted: true
                    textColor: "white"

                    enabled: !bridge.nodeInstallBusy

                    onClicked: {
                        nodeInstallDialog.installStarted = true
                        bridge.clearNodeInstallLog()

                        bridge.installNodeRuntimeMajor(
                            nodeMajorCombo.currentText
                        )
                    }
                }

                Components.AppButton {
                    text: bridge.nodeInstallBusy
                        ? Strings.t("close")
                        : Strings.t("cancel")

                    onClicked: {
                        window.nodeInstallDialogOpen = false
                    }
                }
            }

        }
    }
}
