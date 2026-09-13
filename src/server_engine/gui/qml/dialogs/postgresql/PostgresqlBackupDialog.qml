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

        id: postgresqlBackupWindow
        visible: root.postgresqlBackupPopupOpen
        width: 760
        height: 560
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: String(root.postgresqlBackupDatabaseName || "").length > 0 ? ("Backup " + root.postgresqlBackupDatabaseName) : "PostgreSQL Backup"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (visible) {
                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                root.backupFlowAction = "backup"
                root.refreshPostgresqlBackupItems()
            } else {
                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                root.postgresqlBackupPopupOpen = false
                root.postgresqlBackupResultOpen = false
                root.postgresqlBackupDatabaseName = ""
                root.backupItemsModel = []
                root.backupFlowAction = "backup"
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("postgresql.backup")
            moveWindow: postgresqlBackupWindow
            contentMargins: 16
            contentSpacing: 16
            footerRightMargin: 0
            footerBottomMargin: 0
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                spacing: 16

                Label {
                    text: String(root.postgresqlBackupDatabaseName || "").length > 0
                        ? "Create a zipped backup for " + root.postgresqlBackupDatabaseName + " and manage previous backup archives."
                        : "Create a zipped backup archive."
                    color: Theme.muted
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: Strings.t("selected.postgresql.database")
                            color: Theme.muted
                            font.pixelSize: 12
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.postgresqlBackupDatabaseName
                            color: Theme.text
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    Components.AppButton {
                        text: bridge().postgresqlBackupBusy
                            ? "Backing up..."
                            : "Backup now"

                        highlighted: true
                        textColor: "white"

                        enabled: !bridge().postgresqlBackupBusy
                            && String(root.postgresqlBackupDatabaseName || "").length > 0
                        Layout.alignment: Qt.AlignBottom

                        onClicked: {
                            root.backupFlowAction = "backup"
                            root.postgresqlBackupResultOpen = true
                            bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                            bridge().createPostgresqlBackup && bridge().createPostgresqlBackup(
                                root.postgresqlBackupDatabaseName
                            )
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Text {
                            text: Strings.t("available.backups")
                            color: Theme.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: root.backupItemsModel
                            clip: true

                            delegate: Rectangle {
                                required property int index
                                property var backupItem: root.backupItemsModel[index]

                                width: ListView.view.width
                                height: 68
                                color: "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            text: backupItem.name
                                            color: Theme.text
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: backupItem.created_at + " • "
                                                + Math.round((backupItem.size || 0) / 1024)
                                                + " KB"

                                            color: Theme.muted
                                            font.pixelSize: 12
                                        }
                                    }

                                    Row {
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        spacing: 4

                                        Components.AppButton {
                                            text: Strings.t("reveal.in.finder")

                                            enabled: !bridge().postgresqlBackupBusy

                                            onClicked: {
                                                bridge().revealInFinder && bridge().revealInFinder(
                                                    backupItem.path
                                                )
                                            }
                                        }

                                        Components.AppButton {
                                            text: Strings.t("restore")

                                            highlighted: true
                                            textColor: "white"

                                            enabled: !bridge().postgresqlBackupBusy

                                            onClicked: {
                                                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                                                root.backupActionType = "restore"
                                                root.backupActionPath = String(backupItem.path || "")
                                                root.backupActionName = String(backupItem.name || "")
                                                root.postgresqlBackupActionConfirmOpen = true
                                            }
                                        }

                                        Components.AppButton {
                                            text: Strings.t("delete")
                                            enabled: !bridge().postgresqlBackupBusy
                                            onClicked: {
                                                bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                                                root.backupActionType = "delete"
                                                root.backupActionPath = String(backupItem.path || "")
                                                root.backupActionName = String(backupItem.name || "")
                                                root.postgresqlBackupActionConfirmOpen = true
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Theme.border
                                }
                            }

                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: (root.backupItemsModel || []).length === 0

                            Column {
                                anchors.centerIn: parent
                                width: parent.width
                                spacing: 6

                                Text {
                                    text: Strings.t("no.backups.yet")
                                    color: Theme.text
                                    font.pixelSize: 18
                                    font.weight: Font.DemiBold
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    text: Strings.t("create.the.first.zipped.archive.for.this.postgresql.database")
                                    color: Theme.muted
                                    font.pixelSize: 13
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
