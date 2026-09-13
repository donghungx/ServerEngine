import QtQuick
import QtQuick.Controls
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: root
    required property var window
    required property var bridge
    visible: window.nodeUninstallConfirmOpen
    width: 520
    height: 260
    title: Strings.t("confirm.uninstall")
    color: Theme.surface
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (!visible) {
            window.nodeUninstallConfirmOpen = false
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
                text: Strings.t("uninstall.node.runtime")
                color: Theme.text
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }

            Text {
                text: Strings.t("this.will.remove") + window.nodeUninstallTargetLabel + " from installed runtimes."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Item {
                width: 1
                height: 1
            }

            Row {
                spacing: 6

                Components.AppButton {
                    text: Strings.t("cancel")
                    onClicked: window.nodeUninstallConfirmOpen = false
                }

                Components.AppButton {
                    text: Strings.t("uninstall")
                    highlighted: true
                    textColor: "white"
                    onClicked: {
                        if (window.nodeUninstallTargetHome.length > 0) {
                            bridge.uninstallNodeRuntime(window.nodeUninstallTargetHome)
                        }
                        window.nodeUninstallConfirmOpen = false
                    }
                }
            }
        }
    }
}
