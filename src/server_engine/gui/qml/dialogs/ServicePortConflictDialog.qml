import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../theme"

Window {
    id: root

    required property var window
    required property var bridge

    visible: !!bridge && bridge.servicePortConflictOpen
    width: 560
    height: 196
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: "Port Conflict"
    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: window
    flags: Qt.Dialog | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (!visible && !!bridge && bridge.servicePortConflictOpen) {
            bridge.dismissServicePortConflict()
        }
    }

    Components.AppWindowFrame {
        anchors.fill: parent
        title: root.title
        moveWindow: root
        contentMargins: 20
        contentSpacing: 14
        footerBottomMargin: 20

        Column {
            anchors.fill: parent
            spacing: 14

            Text {
                text: (!!bridge ? bridge.servicePortConflictServiceLabel : "")
                      + " Port "
                      + (!!bridge ? bridge.servicePortConflictPort : 0)
                      + " Is In Use"
                color: Theme.text
                font.pixelSize: 22
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                text: !!bridge ? bridge.servicePortConflictMessage : ""
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }

        footerRight: Row {
            spacing: 6

            Components.AppButton {
                text: "Cancel"
                enabled: !!bridge && !window.servicePortConflictBusy()
                onClicked: if (bridge) bridge.dismissServicePortConflict()
            }

            Components.AppButton {
                text: "Kill And Retry"
                accent: true
                enabled: !!bridge && !window.servicePortConflictBusy()
                onClicked: if (bridge) bridge.resolveServicePortConflictAndRetry()
            }
        }
    }
}
