import QtQuick
import QtQuick.Controls
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: root
    required property var window
    required property var bridge
    visible: window.runtimeSwitchConfirmOpen
    width: 600
    height: 256
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("switch.runtime")
    color: Theme.surface
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (!visible) {
            window.runtimeSwitchConfirmOpen = false
        }
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: Strings.t("switch.runtime")
        moveWindow: root
        contentMargins: 18
        contentSpacing: 14
        footerRightMargin: 18
        footerBottomMargin: 18
        color: Theme.surface

        Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 14

            Text {
                text: Strings.t("activate") + " " + window.runtimeSwitchLabel + "?"
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                text: window.runtimeSwitchServiceRunning
                    ? Strings.t("the.service.is.currently.running.and.will.be.stopped.before.switching")
                    : Strings.t("if.this.service.starts.later.it.will.use.the.selected.runtime")
                color: Theme.danger
                font.pixelSize: 13
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                visible: {
                    var service = String(window.runtimeSwitchService || "").toLowerCase()
                    return service === "mysql"
                        || service === "mariadb"
                        || service === "mongodb"
                        || service === "postgresql"
                }
                text: Strings.t("warning.switching.database.runtimes.does.not.sync.existing.data.you.must.back.up.and.restore.data.manually.if.you.want.to.move.databases.between.runtimes")
                color: Theme.warning
                font.pixelSize: 13
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                text: Strings.t("choose.whether.to.copy.the.current.runtime.config.into.the.selected.runtime.or.switch.without.copying")
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }

        footerRight: Row {
            spacing: 6

            Components.AppButton {
                text: Strings.t("cancel")
                enabled: !bridge.runtimeManagerBusy
                onClicked: window.runtimeSwitchConfirmOpen = false
            }

            Components.AppButton {
                text: Strings.t("use.previous.config")
                enabled: !bridge.runtimeManagerBusy
                highlighted: true
                textColor: "white"
                onClicked: {
                    bridge.activateRuntime(window.runtimeSwitchService, window.runtimeSwitchTarget, true)
                    window.runtimeSwitchConfirmOpen = false
                }
            }

            Components.AppButton {
                text: Strings.t("switch.only")
                enabled: !bridge.runtimeManagerBusy
                onClicked: {
                    bridge.activateRuntime(window.runtimeSwitchService, window.runtimeSwitchTarget, false)
                    window.runtimeSwitchConfirmOpen = false
                }
            }
        }
    }
}
