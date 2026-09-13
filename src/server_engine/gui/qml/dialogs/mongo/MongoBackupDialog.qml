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

        id: mongodbBackupWindow
        visible: root.mongodbBackupPopupOpen
        width: 760
        height: 560
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: String(root.mongodbBackupDatabaseName || "").length > 0 ? ("Backup " + root.mongodbBackupDatabaseName) : "MongoDB Backup"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (visible) {
                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                root.backupFlowAction = "backup"
                root && root.refreshMongodbBackupItems && root.refreshMongodbBackupItems()
            } else {
                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                root.mongodbBackupPopupOpen = false
                root.mongodbBackupResultOpen = false
                root.mongodbBackupDatabaseName = ""
                root.backupItemsModel = []
                root.backupFlowAction = "backup"
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("mongodb.backup")
            moveWindow: mongodbBackupWindow
            contentMargins: 16
            contentSpacing: 16
            footerRightMargin: 0
            footerBottomMargin: 0
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                spacing: 16

                Label {
                    text: String(root.mongodbBackupDatabaseName || "").length > 0
                        ? "Create a zipped backup for " + root.mongodbBackupDatabaseName + " and manage previous backup archives."
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
                            text: Strings.t("selected.mongodb.database")
                            color: Theme.muted
                            font.pixelSize: 12
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(root.mongodbBackupDatabaseName || "")
                            color: Theme.text
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    Components.AppButton {
                        text: bridge().mongodbBackupBusy
                            ? "Backing up..."
                            : "Backup now"

                        highlighted: true
                        textColor: "white"

                        enabled: !bridge().mongodbBackupBusy
                            && String(root.mongodbBackupDatabaseName || "").length > 0
                        Layout.alignment: Qt.AlignBottom

                        onClicked: {
                            root.backupFlowAction = "backup"
                            root.mongodbBackupResultOpen = true
                            bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                            bridge().createMongodbBackup && bridge().createMongodbBackup(
                                root.mongodbBackupDatabaseName
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
                            model: root.backupItemsModel || []
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

                                            enabled: !bridge().mongodbBackupBusy

                                            onClicked: {
                                                bridge().revealInFinder && bridge().revealInFinder(backupItem.path)
                                            }
                                        }

                                        Components.AppButton {
                                            text: Strings.t("restore")

                                            highlighted: true
                                            textColor: "white"

                                            enabled: !bridge().mongodbBackupBusy

                                            onClicked: {
                                                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                                                root.backupActionType = "restore"
                                                root.backupActionPath = String(backupItem.path || "")
                                                root.backupActionName = String(backupItem.name || "")
                                                root.mongodbBackupActionConfirmOpen = true
                                            }
                                        }

                                        Components.AppButton {
                                            text: Strings.t("delete")
                                            enabled: !bridge().mongodbBackupBusy
                                            onClicked: {
                                                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
                                                root.backupActionType = "delete"
                                                root.backupActionPath = String(backupItem.path || "")
                                                root.backupActionName = String(backupItem.name || "")
                                                root.mongodbBackupActionConfirmOpen = true
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
                                    text: Strings.t("create.the.first.zipped.archive.for.this.mongodb.database")
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
