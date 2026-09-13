import QtQuick
import QtQuick.Controls
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: root
    required property var window
    required property var bridge
    visible: window.runtimeRemoveConfirmOpen
    width: 400
    height: 160
    title: Strings.t("remove.runtime")
    color: Theme.surface
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (!visible) {
            window.runtimeRemoveConfirmOpen = false
        }
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: Strings.t("remove.runtime")
        moveWindow: root
        color: Theme.surface

        Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            Text {
                text: Strings.t("remove") + " " + window.runtimeRemoveLabel + "?"
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                text: window.runtimeRemoveServiceRunning
                    ? "This service is currently running. Server Engine will stop it first, then remove the runtime."
                    : "This service is not running."
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                text: (window.runtimeRemoveService === "redis"
                    || window.runtimeRemoveService === "memcached"
                    || window.runtimeRemoveService === "mailpit")
                    ? "If you remove the active runtime, Server Engine will auto-select another installed runtime for this service."
                    : "This action permanently removes the selected runtime from this machine."
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("cancel")
                enabled: !bridge.runtimeManagerBusy
                onClicked: window.runtimeRemoveConfirmOpen = false
            }

            Components.AppButton {
                text: bridge.runtimeManagerBusy ? "Removing..." : "Remove"
                enabled: !bridge.runtimeManagerBusy
                highlighted: true
                textColor: "white"
                onClicked: {
                    bridge.removeRuntime(window.runtimeRemoveService, window.runtimeRemoveTarget)
                    window.runtimeRemoveConfirmOpen = false
                }
            }
        }
    }
}
