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

        id: mongodbBackupActionConfirmWindow
        visible: root.mongodbBackupActionConfirmOpen
        width: 520
        height: Math.max(180, backupActionConfirmContent.implicitHeight + 96)
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: root.backupActionType === "restore" ? "Confirm Restore Backup" : "Confirm Delete Backup"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (!visible) {
                root.mongodbBackupActionConfirmOpen = false
                root.backupActionPath = ""
                root.backupActionName = ""
                root.backupActionType = ""
                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
            }
        }


        Components.AppWindowFrame {
            anchors.fill: parent
            title: root.backupActionType === "restore" ? "Restore MongoDB Archive" : "Delete Backup Archive"
            moveWindow: mongodbBackupActionConfirmWindow
            contentMargins: 16
            contentSpacing: 12
            footerRightMargin: 16
            footerBottomMargin: 16
            color: Theme.surface

            ColumnLayout {
                id: backupActionConfirmContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 12

                Text {
                    text: root.backupActionType === "restore"
                        ? ("Restore " + root.mongodbBackupDatabaseName + "?")
                        : "Delete backup archive?"
                    color: Theme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                Text {
                    text: root.backupActionType === "restore"
                        ? ("This will restore data from '" + root.backupActionName + "' into '" + root.mongodbBackupDatabaseName + "'. Current data in '" + root.mongodbBackupDatabaseName + "' will be permanently replaced.")
                        : ("This will permanently delete '" + root.backupActionName + "'.")
                    color: root.backupActionType === "restore" ? Theme.muted : "#bb4d4d"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: String(bridge().mongodbBackupMessage || "")
                    color: bridge().mongodbBackupError ? "#bb4d4d" : "#4aa94b"
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: String(bridge().mongodbBackupMessage || "").length > 0
                    Layout.fillWidth: true
                }
            }

            footerRight: Row {
                spacing: 4

                Components.AppButton {
                    text: Strings.t("cancel")
                    enabled: !bridge().mongodbBackupBusy
                    onClicked: root.mongodbBackupActionConfirmOpen = false
                }

                Components.AppButton {
                    text: root.backupActionType === "restore" ? "Restore" : "Delete"
                    enabled: !bridge().mongodbBackupBusy
                        && String(root.backupActionPath || "").length > 0
                    onClicked: {
                        var ok = false
                        root.mongodbBackupResultOpen = true
                        bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                        root.backupFlowAction = root.backupActionType
                        if (root.backupActionType === "restore") {
                            ok = bridge().restoreMongodbBackup && bridge().restoreMongodbBackup(root.backupActionPath)
                        } else {
                            ok = bridge().deleteMongodbBackup && bridge().deleteMongodbBackup(root.backupActionPath)
                            root && root.refreshMongodbBackupItems && root.refreshMongodbBackupItems()
                        }
                        if (ok) {
                            root.mongodbBackupActionConfirmOpen = false
                        }
                    }
                }
            }
        }
    }
