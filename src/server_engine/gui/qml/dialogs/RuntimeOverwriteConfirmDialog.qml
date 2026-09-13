import QtQuick
import QtQuick.Controls
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: root
    required property var window
    required property var bridge
    visible: window.runtimeInstallOverwriteConfirmOpen
    width: 520
    height: 250
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowCloseButtonHint
    color: "transparent"

    onVisibleChanged: {
        if (!visible) {
            window.runtimeInstallOverwriteConfirmOpen = false
        }
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: Strings.t("overwrite.runtime")
        moveWindow: root

        Column {
            anchors.fill: parent
            spacing: 12

            Text {
                text: Strings.t("overwrite.existing.runtime")
                color: Theme.text
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }

            Text {
                text: Strings.t("this.runtime.is.already.installed.server.engine.will.save.the.managed.config.before.replacing.the.runtime.folder")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }

        footerRight: Row {
            spacing: 6

            Components.AppButton {
                text: Strings.t("cancel")
                enabled: !bridge.runtimeInstallBusy
                onClicked: window.runtimeInstallOverwriteConfirmOpen = false
            }

            Components.AppButton {
                text: Strings.t("overwrite")
                enabled: !bridge.runtimeInstallBusy
                highlighted: true
                textColor: "white"
                onClicked: {
                    bridge.installServerRuntime(window.runtimeInstallSelectedItem, true)
                    window.runtimeInstallOverwriteConfirmOpen = false
                }
            }
        }
    }
}
