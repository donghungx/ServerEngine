import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../dialogs/postgresql"
import "../dialogs/postgresql/runtime"
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    signal databaseCliRequested()
    signal backupRequested(var rowData)

    required property var dashboardBridge
    border.width: 0
    color: "transparent"
    readonly property bool postgresqlRunning: String(dashboardBridge.activePostgresqlServiceState || "").toLowerCase() === "running"
    readonly property bool databaseRunning: root.postgresqlRunning
    property bool runtimePopupOpen: false
    property bool newPostgresqlDatabasePopupOpen: false
    property bool postgresqlPasswordPopupOpen: false
    property bool postgresqlBackupPopupOpen: false
    property bool postgresqlBackupActionConfirmOpen: false
    property bool postgresqlBackupResultOpen: false
    property bool postgresqlImportPopupOpen: false
    property bool postgresqlDropConfirmOpen: false
    property string postgresqlBackupDatabaseName: ""
    property string postgresqlImportDatabaseName: ""
    property string postgresqlDropDatabaseName: ""
    property string postgresqlPasswordFeedback: ""
    property bool postgresqlPasswordFeedbackError: false
    property string postgresqlConfigDraft: ""
    property string postgresqlConfigFeedback: ""
    property var backupItemsModel: []
    property string backupActionPath: ""
    property string backupActionName: ""
    property string backupActionType: ""
    property string backupFlowAction: "backup"
    property var postgresqlItemsModel: []
    readonly property string postgresqlFilterText: postgresqlFilterField ? String(postgresqlFilterField.text || "").trim().toLowerCase() : ""
    readonly property var filteredPostgresqlItemsModel: {
        if (postgresqlFilterText.length === 0) {
            return postgresqlItemsModel
        }
        return postgresqlItemsModel.filter(function(item) {
            var nameValue = String(item.name || "").toLowerCase()
            var typeValue = String(item.type || "").toLowerCase()
            return nameValue.indexOf(postgresqlFilterText) !== -1 || typeValue.indexOf(postgresqlFilterText) !== -1
        })
    }
    property var postgresqlEncodings: [
        "UTF8",
        "LATIN1",
        "SQL_ASCII"
    ]
    property bool slowLogEnabled: false
    property string slowLogLongQueryTime: "3"
    property string slowLogNotUsingIndexes: "On"
    property string postgresqlGeneralListenAddressesDraft: "127.0.0.1"
    property string postgresqlGeneralTimezoneDraft: "UTC"
    property string postgresqlGeneralPortDraft: "5432"
    property string postgresqlGeneralMaxConnectionsDraft: "100"
    property string postgresqlGeneralReservedConnectionsDraft: "0"
    property string postgresqlGeneralSuperuserReservedConnectionsDraft: "3"
    property string postgresqlGeneralUnixSocketDirectoriesDraft: "/tmp"
    property bool postgresqlGeneralLoggingCollectorDraft: false
    property string postgresqlGeneralLogDestinationDraft: "stderr"
    property string postgresqlGeneralLogMinMessagesDraft: "warning"
    property bool postgresqlGeneralLogConnectionsDraft: false
    property bool postgresqlGeneralLogDisconnectionsDraft: false
    property string postgresqlGeneralLogLinePrefixDraft: "%m [%p] %q%u@%d "
    property string postgresqlGeneralSharedBuffersDraft: "128MB"
    property string postgresqlGeneralWorkMemDraft: "4MB"
    property string postgresqlGeneralMaintenanceWorkMemDraft: "64MB"
    property string postgresqlGeneralEffectiveCacheSizeDraft: "4GB"
    property string postgresqlGeneralWalLevelDraft: "replica"
    property string postgresqlGeneralCheckpointTimeoutDraft: "5min"
    property string postgresqlGeneralCheckpointCompletionTargetDraft: "0.9"
    property string postgresqlGeneralMaxWalSizeDraft: "1GB"
    property string postgresqlGeneralMinWalSizeDraft: "80MB"
    property bool postgresqlGeneralArchiveModeDraft: false
    property string postgresqlGeneralArchiveTimeoutDraft: "0"
    property bool postgresqlGeneralAutovacuumDraft: true
    property string postgresqlGeneralAutovacuumMaxWorkersDraft: "3"
    property string postgresqlGeneralAutovacuumNaptimeDraft: "1min"
    property string postgresqlGeneralStatementTimeoutDraft: "0"
    property string postgresqlGeneralIdleInTransactionSessionTimeoutDraft: "0"
    property string postgresqlGeneralDefaultTransactionIsolationDraft: "read committed"
    property string postgresqlGeneralMaxWalSendersDraft: "10"
    property string postgresqlGeneralWalKeepSizeDraft: "0"
    property string postgresqlRuntimePopupSection: "settings"
    property var postgresqlRuntimePopupSections: [
        { id: "settings" },
        { id: "service" },
        { id: "configuration" },
        { id: "data.directory" },
        { id: "port" },
        { id: "error.log" }
    ]

    function folderUrl(path) {
        return "file://" + encodeURI(path)
    }

    function postgresqlBackupItems() {
        return dashboardBridge.postgresqlBackupItems(root.postgresqlBackupDatabaseName)
    }

    function refreshPostgresqlBackupItems() {
        if (!root.postgresqlBackupDatabaseName || root.postgresqlBackupDatabaseName.length === 0) {
            root.backupItemsModel = []
            return
        }
        root.backupItemsModel = dashboardBridge.postgresqlBackupItems(root.postgresqlBackupDatabaseName)
    }

    function refreshPostgresqlItems() {
        root.postgresqlItemsModel = dashboardBridge.postgresqlItems
    }

    function postgresqlIndex(databaseName) {
        for (var i = 0; i < root.postgresqlItemsModel.length; i++) {
            if (String(root.postgresqlItemsModel[i].name || "") === String(databaseName || "")) {
                return i
            }
        }
        return root.postgresqlItemsModel.length > 0 ? 0 : -1
    }

    function refreshPostgresqlConfigDraft() {
        root.postgresqlConfigDraft = dashboardBridge.activePostgresqlConfigContent
        root.postgresqlConfigFeedback = ""
    }

    function refreshPostgresqlGeneralDraft() {
        var settings = (dashboardBridge && dashboardBridge.postgresqlRuntimeSettings) ? dashboardBridge.postgresqlRuntimeSettings() : {}
        root.postgresqlGeneralListenAddressesDraft = String(settings.listen_addresses || "127.0.0.1")
        root.postgresqlGeneralTimezoneDraft = String(settings.timezone || "UTC")
        root.postgresqlGeneralPortDraft = "5432"
        root.postgresqlGeneralMaxConnectionsDraft = "100"
        root.postgresqlGeneralReservedConnectionsDraft = "0"
        root.postgresqlGeneralSuperuserReservedConnectionsDraft = "3"
        root.postgresqlGeneralUnixSocketDirectoriesDraft = "/tmp"
        root.postgresqlGeneralLoggingCollectorDraft = settings.logging_collector === undefined ? false : Boolean(settings.logging_collector)
        root.postgresqlGeneralLogDestinationDraft = "stderr"
        root.postgresqlGeneralLogMinMessagesDraft = String(settings.log_min_messages || "warning")
        root.postgresqlGeneralLogConnectionsDraft = settings.log_connections === undefined ? false : Boolean(settings.log_connections)
        root.postgresqlGeneralLogDisconnectionsDraft = settings.log_disconnections === undefined ? false : Boolean(settings.log_disconnections)
        root.postgresqlGeneralLogLinePrefixDraft = String(settings.log_line_prefix || "%m [%p] %q%u@%d ")
        root.postgresqlGeneralSharedBuffersDraft = "128MB"
        root.postgresqlGeneralWorkMemDraft = "4MB"
        root.postgresqlGeneralMaintenanceWorkMemDraft = "64MB"
        root.postgresqlGeneralEffectiveCacheSizeDraft = "4GB"
        root.postgresqlGeneralWalLevelDraft = "replica"
        root.postgresqlGeneralCheckpointTimeoutDraft = "5min"
        root.postgresqlGeneralCheckpointCompletionTargetDraft = "0.9"
        root.postgresqlGeneralMaxWalSizeDraft = "1GB"
        root.postgresqlGeneralMinWalSizeDraft = "80MB"
        root.postgresqlGeneralArchiveModeDraft = false
        root.postgresqlGeneralArchiveTimeoutDraft = "0"
        root.postgresqlGeneralAutovacuumDraft = true
        root.postgresqlGeneralAutovacuumMaxWorkersDraft = "3"
        root.postgresqlGeneralAutovacuumNaptimeDraft = "1min"
        root.postgresqlGeneralStatementTimeoutDraft = "0"
        root.postgresqlGeneralIdleInTransactionSessionTimeoutDraft = String(settings.idle_in_transaction_session_timeout || "0")
        root.postgresqlGeneralDefaultTransactionIsolationDraft = "read committed"
        root.postgresqlGeneralMaxWalSendersDraft = "10"
        root.postgresqlGeneralWalKeepSizeDraft = "0"
    }

    function postgresqlBackupFlowTitleText() {
        if (dashboardBridge.postgresqlBackupBusy) {
            if (backupFlowAction === "restore") {
                return "Restoring " + root.postgresqlBackupDatabaseName
            }
            if (backupFlowAction === "delete") {
                return "Deleting Backup Archive"
            }
            return "Backing Up " + root.postgresqlBackupDatabaseName
        }
        if (backupFlowAction === "restore") {
            return "Restore Result"
        }
        if (backupFlowAction === "delete") {
            return "Delete Result"
        }
        return "Backup Result"
    }

    function postgresqlImportFlowTitleText() {
        if (dashboardBridge.postgresqlImportBusy) {
            return "Importing " + root.postgresqlImportDatabaseName
        }
        if (dashboardBridge.postgresqlImportError) {
            return "Import Failed"
        }
        return "Import Completed"
    }

    onPostgresqlBackupDatabaseNameChanged: {
        if (root.postgresqlBackupPopupOpen) {
            refreshPostgresqlBackupItems()
        }
    }

    Component.onCompleted: {
        Qt.callLater(refreshPostgresqlItems)
    }

    Connections {
        target: dashboardBridge

        function onPostgresqlRuntimeFeedbackChanged() {
            root.refreshPostgresqlItems()
            if (root.postgresqlBackupPopupOpen) {
                root.refreshPostgresqlBackupItems()
            }
        }

        function onDataChanged() {
            if (root.postgresqlBackupPopupOpen) {
                root.refreshPostgresqlBackupItems()
            }
        }
    }

    function postgresqlRuntimeSectionDescription(sectionId) {
        switch (sectionId) {
        case "settings":
            return "PostgreSQL runtime settings for connections, logging, resource use, WAL, vacuuming, client defaults, and replication."
        case "configuration":
            return "PostgreSQL runtime config path and generated config file location."
        case "data.directory":
            return "PostgreSQL files and runtime data directory used by the active version."
        case "port":
            return "Listen port details for the active PostgreSQL runtime."
        case "current.status":
            return "Current runtime state and the latest startup or shutdown feedback."
        case "error.log":
            return "Runtime error log output for the active PostgreSQL database version."
        case "slow.log":
            return "Slow query log controls and output will live here."
        case "binary.log":
            return "Binary log controls and replication-oriented output will live here."
        default:
            return "Manage the active local PostgreSQL runtime and inspect startup logs."
        }
    }

    function postgresqlRuntimeSectionSource(sectionId) {
        switch (sectionId) {
        case "settings":
            return "postgresql_runtime_sections/SettingsSection.qml"
        case "service":
            return "postgresql_runtime_sections/ServiceSection.qml"
        case "configuration":
            return "postgresql_runtime_sections/ConfigFileSection.qml"
        case "data.directory":
            return "postgresql_runtime_sections/StorageLocationSection.qml"
        case "port":
            return "postgresql_runtime_sections/PortSection.qml"
        case "current.status":
            return "postgresql_runtime_sections/CurrentStatusSection.qml"
        case "error.log":
            return "postgresql_runtime_sections/ErrorLogSection.qml"
        case "slow.log":
            return "postgresql_runtime_sections/SlowLogSection.qml"
        default:
            return "postgresql_runtime_sections/PlaceholderSection.qml"
        }
    }

    function postgresqlRuntimeSectionLabel(sectionId) {
        for (var i = 0; i < postgresqlRuntimePopupSections.length; i++) {
            if (postgresqlRuntimePopupSections[i].id === sectionId) {
                return Strings.t(postgresqlRuntimePopupSections[i].id)
            }
        }
        return Strings.t(String(sectionId || ""))
    }

    function postgresqlRuntimeSectionIcon(sectionId) {
        switch (sectionId) {
        case "settings":
            return "settings"
        case "service":
            return "power-accent"
        case "configuration":
            return "file-sliders"
        case "data.directory":
            return "folder-input"
        case "port":
            return "ethernet-port"
        case "current.status":
            return "panel-top"
        case "error.log":
            return "file-text"
        case "slow.log":
            return "file-text"
        case "binary.log":
            return "database"
        default:
            return "settings"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 64
        anchors.rightMargin: 16
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Components.AppButton {
                text: Strings.t("new.database")
                iconSource: "icons/lucide/database.svg"
                enabled: root.postgresqlRunning

                onClicked: root.newPostgresqlDatabasePopupOpen = true
            }

            Components.AppButton {
                text: Strings.t("root.password")
                iconSource: "icons/lucide/shield.svg"
                enabled: root.postgresqlRunning

                onClicked: root.postgresqlPasswordPopupOpen = true
            }

            Components.AppButton {
                text: Strings.t("adminer")
                iconSource: "icons/lucide/phpmyadmin.svg"
                enabled: false

                onClicked: dashboardBridge.openAdminer()
            }

            Components.AppButton {
                text: Strings.t("cli")
                iconSource: "icons/lucide/terminal.svg"
                enabled: root.databaseRunning

                onClicked: root.databaseCliRequested()
            }

            Components.AppButton {
                text: dashboardBridge.activePostgresqlRuntimeBrand
                iconSource: "icons/lucide/settings.svg"

                onClicked: {
                    root.runtimePopupOpen = true
                    root.postgresqlRuntimePopupSection = "settings"
                    dashboardBridge.refreshPostgresqlRuntime()
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Components.AppTextField {
                id: postgresqlFilterField
                width: 320
                placeholderText: Strings.t("database.name")

                selectByMouse: true
                inputMethodHints: Qt.ImhNoPredictiveText
            }

            Components.QuickActionButton {
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: "Reload"
                onClicked: dashboardBridge.refreshPostgresqlRuntime()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                anchors.fill: parent
                visible: root.postgresqlRunning

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: Theme.radius
                        color: Theme.surfaceAlt
                        border.color: Theme.border
                        border.width: 1

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 0

                            Components.HeaderCell { label: Strings.t("database.name"); cellWidth: 346 }
                            Components.HeaderCell { label: Strings.t("type"); cellWidth: 140 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.bottomMargin: 16
                        radius: Theme.radius
                        color: Theme.surface
                        border.color: Theme.border
                        border.width: 1
                        clip: true

                        Components.AppScrollArea {
                            anchors.fill: parent
                            clipContent: true

                            ListView {
                                width: parent.width
                                height: contentHeight
                                implicitHeight: contentHeight
                                model: root.filteredPostgresqlItemsModel
                                visible: count > 0
                                interactive: false
                                clip: true

                                delegate: Column {
                                    required property int index
                                    width: ListView.view.width
                                    property var postgresqlItem: root.filteredPostgresqlItemsModel[index]

                                    Components.DatabaseRow {
                                        width: parent.width
                                        height: 72
                                        rowData: parent.postgresqlItem
                                        onBackupRequested: function(rowData) {
                                            root.backupRequested(rowData)
                                        }
                                        onImportRequested: function(rowData) {
                                            root.postgresqlImportDatabaseName = rowData.name
                                            root.postgresqlImportPopupOpen = true
                                            dashboardBridge.clearPostgresqlRuntimeFeedback()
                                        }
                                        onDropRequested: function(rowData) {
                                            root.postgresqlDropDatabaseName = rowData.name
                                            root.postgresqlDropConfirmOpen = true
                                            dashboardBridge.clearPostgresqlRuntimeFeedback()
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: Theme.border
                                    }
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            visible: root.filteredPostgresqlItemsModel.length === 0
                            spacing: 10

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.postgresqlFilterText.length > 0 ? "No matching PostgreSQL databases" : "No PostgreSQL databases detected"
                                color: Theme.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.postgresqlFilterText.length > 0
                                    ? "Try a different database name keyword."
                                    : "This page lists real PostgreSQL databases from the active local PostgreSQL runtime when it is reachable."
                                color: Theme.muted
                                font.pixelSize: 14
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                visible: !root.postgresqlRunning
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Strings.t("postgresql.runtime.is.not.running")
                    color: Theme.text
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Strings.t("start.the.runtime.to.load.databases.backups.and.import.actions")
                    color: Theme.muted
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
    PostgresqlDropConfirmDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlImportDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlImportResultDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlBackupDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlBackupActionConfirmDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlBackupResultDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlRuntimeDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlPasswordDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    PostgresqlNewDatabaseDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

}
