import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Window {
    property var root: ({})
    property var dashboardBridge: ({})

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (root && root.dashboardBridge) {
            return root.dashboardBridge
        }
        return ({})
    }

    function backupFlowTitleText() {
        if (bridge().mongodbBackupBusy) {
            if (root.backupFlowAction === "restore") {
                return "Restoring " + root.mongodbBackupDatabaseName
            }
            if (root.backupFlowAction === "delete") {
                return "Deleting Backup Archive"
            }
            return "Backing Up " + root.mongodbBackupDatabaseName
        }
        if (root.backupFlowAction === "restore") {
            return "Restore Result"
        }
        if (root.backupFlowAction === "delete") {
            return "Delete Result"
        }
        return "Backup Result"
    }
        id: mongodbBackupResultWindow
        visible: root.mongodbBackupResultOpen
        width: 520
        height: 204
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: backupFlowTitleText()
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        Components.AppWindowFrame {
            anchors.fill: parent
            title: backupFlowTitleText()
            moveWindow: mongodbBackupResultWindow
            contentMargins: 16
            contentSpacing: 14
            footerRightMargin: 16
            footerBottomMargin: 16
            color: Theme.surface

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 12

                Text {
                    text: backupFlowTitleText()
                    color: Theme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Text {
                    text: root.mongodbBackupDatabaseName
                    color: Theme.muted
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 12
                    radius: 6
                    color: Theme.muted
                    visible: bridge().mongodbBackupBusy || bridge().mongodbBackupProgress > 0

                    Rectangle {
                        width: parent.width * (bridge().mongodbBackupProgress / 100.0)
                        height: parent.height
                        radius: 6
                        color: Theme.accentStrong
                    }
                }

                Text {
                    text: bridge().mongodbBackupBusy
                        ? (bridge().mongodbBackupProgressLabel + " " + bridge().mongodbBackupProgress + "%")
                        : (String(bridge().mongodbBackupMessage || "").length > 0 ? bridge().mongodbBackupMessage : "")
                    color: bridge().mongodbBackupBusy
                        ? Theme.text
                        : (bridge().mongodbBackupError ? "#bb4d4d" : "#4aa94b")
                    font.pixelSize: 13
                    wrapMode: Text.NoWrap
                    Layout.fillWidth: true
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }

            footerRight: Row {
                Components.AppButton {
                    text: Strings.t("dismiss")
                    visible: !bridge().mongodbBackupBusy
                    onClicked: {
                        bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                        root.mongodbBackupResultOpen = false
                    }
                }
            }
        }
    }
