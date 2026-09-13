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

    id: postgresqlBackupActionConfirmWindow
        visible: root.postgresqlBackupActionConfirmOpen
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
                root.postgresqlBackupActionConfirmOpen = false
                root.backupActionPath = ""
                root.backupActionName = ""
                root.backupActionType = ""
                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: root.backupActionType === "restore" ? "Restore PostgreSQL Archive" : "Delete Backup Archive"
            moveWindow: postgresqlBackupActionConfirmWindow
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
                        ? ("Restore " + root.postgresqlBackupDatabaseName + "?")
                        : "Delete backup archive?"
                    color: Theme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                Text {
                    text: root.backupActionType === "restore"
                        ? ("This will restore data from '" + root.backupActionName + "' into '" + root.postgresqlBackupDatabaseName + "'. Current data in '" + root.postgresqlBackupDatabaseName + "' will be permanently replaced.")
                        : ("This will permanently delete '" + root.backupActionName + "'.")
                    color: root.backupActionType === "restore" ? Theme.muted : "#bb4d4d"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: String(bridge().postgresqlBackupMessage || "")
                    color: bridge().postgresqlBackupError ? "#bb4d4d" : "#4aa94b"
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: String(bridge().postgresqlBackupMessage || "").length > 0
                    Layout.fillWidth: true
                }
            }

            footerRight: Row {
                spacing: 4

                Components.AppButton {
                    text: Strings.t("cancel")
                    enabled: !bridge().postgresqlBackupBusy
                    onClicked: root.postgresqlBackupActionConfirmOpen = false
                }

                Components.AppButton {
                    text: root.backupActionType === "restore" ? "Restore" : "Delete"
                    enabled: !bridge().postgresqlBackupBusy
                        && String(root.backupActionPath || "").length > 0
                    onClicked: {
                        var ok = false
                        root.postgresqlBackupResultOpen = true
                        bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                        root.backupFlowAction = root.backupActionType
                        if (root.backupActionType === "restore") {
                            ok = bridge().restorePostgresqlBackup ? bridge().restorePostgresqlBackup(root.backupActionPath) : false
                        } else {
                            ok = bridge().deletePostgresqlBackup ? bridge().deletePostgresqlBackup(root.backupActionPath) : false
                            root.refreshPostgresqlBackupItems()
                        }
                        if (ok) {
                            root.postgresqlBackupActionConfirmOpen = false
                        }
                    }
                }
            }
        }
    }
