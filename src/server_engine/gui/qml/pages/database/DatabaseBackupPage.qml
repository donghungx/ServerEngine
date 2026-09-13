import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: backupPage

    required property var dashboardBridge
    property string databaseName: ""
    property string databaseEngine: "mysql"
    property var postgresqlBackupItemsModel: []

    property bool backupActionConfirmOpen: false
    property string backupActionPath: ""
    property string backupActionName: ""
    property string backupActionType: ""
    property string backupFlowAction: "backup"
    property bool refreshAfterBackupRequested: false

    function isPostgresql() { return databaseEngine === "postgresql" }
    function backupItems() { return isPostgresql() ? postgresqlBackupItemsModel : dashboardBridge.databaseBackupItems }
    function backupLoading() { return isPostgresql() ? false : dashboardBridge.databaseBackupItemsLoading }
    function backupBusy() { return isPostgresql() ? dashboardBridge.postgresqlBackupBusy : dashboardBridge.databaseBackupBusy }
    function backupMessage() { return isPostgresql() ? dashboardBridge.postgresqlBackupMessage : dashboardBridge.databaseBackupMessage }
    function backupError() { return isPostgresql() ? dashboardBridge.postgresqlBackupError : dashboardBridge.databaseBackupError }
    function startBackup() { return isPostgresql() ? dashboardBridge.createPostgresqlBackup(databaseName) : dashboardBridge.createDatabaseBackup(databaseName) }
    function restoreBackup(path) { return isPostgresql() ? dashboardBridge.restorePostgresqlBackup(path) : dashboardBridge.restoreDatabaseBackup(path, databaseName) }
    function deleteBackup(path) { return isPostgresql() ? dashboardBridge.deletePostgresqlBackup(path) : dashboardBridge.deleteDatabaseBackup(path) }

    function scheduleRefreshBackupItems() {
        console.log("[DatabaseBackupPage] scheduleRefreshBackupItems databaseName=", databaseName)
        refreshBackupTimer.restart()
    }

    function refreshBackupItems() {
        console.log("[DatabaseBackupPage] refreshBackupItems request databaseName=", databaseName)
        if (!isPostgresql()) {
            dashboardBridge.refreshDatabaseBackupItemsAsync(databaseName)
        } else {
            postgresqlBackupItemsModel = dashboardBridge.postgresqlBackupItems(databaseName)
        }
    }

    Component.onCompleted: {
        if (databaseName.length > 0) {
            console.log("[DatabaseBackupPage] Component.onCompleted databaseName=", databaseName)
            scheduleRefreshBackupItems()
        }
    }

    onDatabaseNameChanged: {
        console.log("[DatabaseBackupPage] onDatabaseNameChanged databaseName=", databaseName)
        scheduleRefreshBackupItems()
    }

    Connections {
        target: dashboardBridge

        function onDatabaseBackupItemsChanged() {
            console.log(
                "[DatabaseBackupPage] onDatabaseBackupItemsChanged databaseName=",
                databaseName,
                "items=",
                backupPage.backupItems().length,
                "loading=",
                backupPage.backupLoading()
            )
        }

        function onDatabaseRuntimeFeedbackChanged() {
            if (!backupPage.refreshAfterBackupRequested) {
                return
            }
            if (backupPage.backupBusy()) {
                return
            }
            backupPage.refreshAfterBackupRequested = false
            backupPage.scheduleRefreshBackupItems()
        }

        function onPostgresqlRuntimeFeedbackChanged() {
            if (!backupPage.isPostgresql() || !backupPage.refreshAfterBackupRequested) {
                return
            }
            if (backupPage.backupBusy()) {
                return
            }
            backupPage.refreshAfterBackupRequested = false
            backupPage.scheduleRefreshBackupItems()
        }
    }

    Timer {
        id: refreshBackupTimer
        interval: 0
        repeat: false
        onTriggered: backupPage.refreshBackupItems()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 64
        anchors.leftMargin: 0
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: databaseName.length > 0
                        ? "Backups for " + databaseName
                        : Strings.t("database.backup")
                    color: Theme.text
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }

                Label {
                    text: databaseName.length > 0
                        ? "Create a zipped backup for " + databaseName + " and manage previous backup archives."
                        : "Create a zipped backup archive."
                    color: Theme.muted
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Components.AppButton {
                text: backupPage.backupBusy() ? "Backing up..." : "Backup now"
                enabled: !backupPage.backupBusy()
                    && databaseName.length > 0

                onClicked: {
                    backupFlowAction = "backup"
                    dashboardBridge.clearDatabaseRuntimeFeedback()
                    refreshAfterBackupRequested = true
                    if (!backupPage.startBackup()) {
                        refreshAfterBackupRequested = false
                    }
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

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: Strings.t("available.backups")
                        color: Theme.text
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    Components.QuickActionButton {
                        iconSource: "../icons/lucide/rotate-cw.svg"
                        tooltip: Strings.t("reload")
                        enabled: !backupPage.backupBusy()
                        onClicked: backupPage.scheduleRefreshBackupItems()
                    }
                }

                Components.AppScrollArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clipContent: true
                    viewportMargins: 0

                    ColumnLayout {
                        width: parent.width
                        spacing: 0

                        Text {
                            width: parent.width
                            visible: backupPage.backupLoading() && backupPage.backupItems().length === 0
                            text: "Loading backups..."
                            color: Theme.muted
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            padding: 18
                        }

                        Column {
                            width: parent.width
                            spacing: 0
                            visible: backupPage.backupItems().length > 0

                            Repeater {
                                model: backupPage.backupItems()

                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData
                                    property var backupItem: modelData

                                    width: parent.width
                                    height: 68
                                    color: "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Text {
                                                text: String(backupItem.name || "")
                                                color: Theme.text
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: String(backupItem.created_at || "") + " • "
                                                    + Math.round((Number(backupItem.size || 0)) / 1024)
                                                    + " KB"
                                                color: Theme.muted
                                                font.pixelSize: 12
                                            }
                                        }

                                        Row {
                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                            spacing: 6

                                            Components.QuickActionButton {
                                                text: Strings.t("reveal.in.finder")
                                                iconSource: "../icons/lucide/folder-open.svg"
                                                enabled: !backupPage.backupBusy()

                                                onClicked: dashboardBridge.revealInFinder(String(backupItem && backupItem.path ? backupItem.path : ""))
                                            }

                                            Components.QuickActionButton {
                                                text: Strings.t("restore")
                                                iconSource: "../icons/lucide/rotate-cw.svg"
                                                danger: false
                                                enabled: !backupPage.backupBusy()

                                                onClicked: {
                                                    dashboardBridge.clearDatabaseRuntimeFeedback()
                                                    backupActionType = "restore"
                                                    backupActionPath = String(backupItem.path || "")
                                                    backupActionName = String(backupItem.name || "")
                                                    backupActionConfirmOpen = true
                                                }
                                            }

                                            Components.QuickActionButton {
                                                text: Strings.t("delete")
                                                iconSource: "../icons/lucide/trash-2.svg"
                                                danger: true
                                                enabled: !backupPage.backupBusy()

                                                onClicked: {
                                                    dashboardBridge.clearDatabaseRuntimeFeedback()
                                                    backupActionType = "delete"
                                                    backupActionPath = String(backupItem.path || "")
                                                    backupActionName = String(backupItem.name || "")
                                                    backupActionConfirmOpen = true
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
                        }

                        Item {
                            width: parent.width
                            height: 220
                            visible: !backupPage.backupLoading() && backupPage.backupItems().length === 0
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
                                    text: Strings.t("create.the.first.zipped.archive.for.this.database")
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

    Window {
        id: backupActionConfirmWindow
        visible: backupActionConfirmOpen
        width: 400
        height: 108
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: backupActionType === "restore" ? "Confirm Restore Backup" : "Confirm Delete Backup"
        color: Theme.surface
        transientParent: backupPage.Window.window
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (!visible) {
                backupActionConfirmOpen = false
                backupActionPath = ""
                backupActionName = ""
                backupActionType = ""
            }
        }

        x: backupPage.Window.window ? backupPage.Window.window.x + Math.round((backupPage.Window.window.width - width) / 2) : 0
        y: backupPage.Window.window ? backupPage.Window.window.y + Math.round((backupPage.Window.window.height - height) / 2) : 0

        Components.AppWindowFrame {
            anchors.fill: parent
            title: backupActionType === "restore" ? "Restore Database Archive" : "Delete Backup Archive"
            moveWindow: backupActionConfirmWindow
            color: Theme.surface

            ColumnLayout {
                id: backupActionConfirmContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                Text {
                    text: backupActionType === "restore"
                        ? ("This will restore data from '" + backupActionName + "' into '" + databaseName + "'. Current data in '" + databaseName + "' will be permanently replaced.")
                        : ("This will permanently delete '" + backupActionName + "'.")
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.Normal
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: backupPage.backupMessage()
                    color: backupPage.backupError() ? "#bb4d4d" : "#4aa94b"
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: backupPage.backupMessage().length > 0
                    Layout.fillWidth: true
                }
            }

            footerRight: Row {
                spacing: 8

                Components.AppButton {
                    height: 24
                    text: Strings.t("cancel")
                    enabled: !backupPage.backupBusy()
                    onClicked: backupActionConfirmOpen = false
                }

                Components.AppButton {
                    height: 24
                    text: backupActionType === "restore" ? "Restore" : "Delete"
                    highlighted: true
                    textColor: "white"

                    enabled: !backupPage.backupBusy()
                        && backupActionPath.length > 0

                    onClicked: {
                        var ok = false
                        dashboardBridge.clearDatabaseRuntimeFeedback()
                        backupFlowAction = backupActionType

                        if (backupActionType === "restore") {
                            ok = backupPage.restoreBackup(backupActionPath)
                        } else {
                            ok = backupPage.deleteBackup(backupActionPath)
                            refreshBackupItems()
                        }

                        if (ok) {
                            backupActionConfirmOpen = false
                        }
                    }
                }
            }
        }
    }
}
