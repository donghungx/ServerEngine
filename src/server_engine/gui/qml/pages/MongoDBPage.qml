import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../dialogs/mongo"
import "../dialogs/mongo/runtime"
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    signal databaseCliRequested()
    signal backupRequested(var rowData)

    required property var dashboardBridge
    border.width: 0
    color: "transparent"
    readonly property bool mongodbRunning: String(dashboardBridge.activeMongodbServiceState || "").toLowerCase() === "running"
    readonly property bool databaseRunning: root.mongodbRunning
    property bool runtimePopupOpen: false
    property bool newMongodbDatabasePopupOpen: false
    property bool mongodbPasswordPopupOpen: false
    property bool mongodbBackupPopupOpen: false
    property bool mongodbBackupActionConfirmOpen: false
    property bool mongodbBackupResultOpen: false
    property bool mongodbImportPopupOpen: false
    property bool mongodbDropConfirmOpen: false
    property string mongodbBackupDatabaseName: ""
    property string mongodbImportDatabaseName: ""
    property string mongodbDropDatabaseName: ""
    property string mongodbPasswordFeedback: ""
    property bool mongodbPasswordFeedbackError: false
    property string mongodbConfigDraft: ""
    property string mongodbConfigFeedback: ""
    property var backupItemsModel: []
    property string backupActionPath: ""
    property string backupActionName: ""
    property string backupActionType: ""
    property string backupFlowAction: "backup"
    property var mongodbItemsModel: []
    readonly property string mongodbFilterText: mongodbFilterField ? String(mongodbFilterField.text || "").trim().toLowerCase() : ""
    readonly property var filteredMongodbItemsModel: {
        if (mongodbFilterText.length === 0) {
            return mongodbItemsModel
        }
        return mongodbItemsModel.filter(function(item) {
            var nameValue = String(item.name || "").toLowerCase()
            var typeValue = String(item.type || "").toLowerCase()
            return nameValue.indexOf(mongodbFilterText) !== -1 || typeValue.indexOf(mongodbFilterText) !== -1
        })
    }
    property bool slowLogEnabled: false
    property string slowLogLongQueryTime: "3"
    property string slowLogNotUsingIndexes: "On"
    property string mongodbGeneralBindIpDraft: "127.0.0.1"
    property bool mongodbGeneralBindIpAllDraft: false
    property string mongodbGeneralPortDraft: "27017"
    property string mongodbGeneralTlsModeDraft: "disabled"
    property string mongodbGeneralSystemLogPathDraft: "~/Library/Application Support/Server Engine/logs/mongodb/mongod.log"
    property bool mongodbGeneralSystemLogAppendDraft: true
    property string mongodbGeneralSystemLogVerbosityDraft: "0"
    property bool mongodbGeneralForkDraft: false
    property string mongodbGeneralPidFilePathDraft: "~/Library/Application Support/Server Engine/runtime/mongodb/mongod.pid"
    property string mongodbGeneralDbPathDraft: "~/Library/Application Support/Server Engine/data/mongodb"
    property string mongodbGeneralAuthorizationDraft: "disabled"
    property string mongodbGeneralClusterAuthModeDraft: "keyFile"
    property string mongodbGeneralKeyFileDraft: "~/Library/Application Support/Server Engine/config/mongodb/keyfile"
    property bool mongodbGeneralJavascriptEnabledDraft: true
    property string mongodbGeneralReplSetNameDraft: "rs0"
    property string mongodbRuntimeHomeText: ""
    property string mongodbRuntimeDataDirText: ""
    property string mongodbRuntimeConfigPathText: ""
    property string mongodbRuntimePortText: ""
    property string mongodbRuntimePopupSection: "settings"
    property var mongodbRuntimePopupSections: [
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

    function mongodbBackupItems() {
        return dashboardBridge.mongodbBackupItems(root.mongodbBackupDatabaseName)
    }

    function refreshMongodbBackupItems() {
        if (!root.mongodbBackupDatabaseName || root.mongodbBackupDatabaseName.length === 0) {
            root.backupItemsModel = []
            return
        }
        root.backupItemsModel = dashboardBridge.mongodbBackupItems(root.mongodbBackupDatabaseName)
    }

    function refreshMongodbItems() {
        root.mongodbItemsModel = dashboardBridge.mongodbItems
        dashboardBridge.refreshMongodbItemsAsync()
    }

    function mongodbIndex(databaseName) {
        for (var i = 0; i < root.mongodbItemsModel.length; i++) {
            if (String(root.mongodbItemsModel[i].name || "") === String(databaseName || "")) {
                return i
            }
        }
        return root.mongodbItemsModel.length > 0 ? 0 : -1
    }

    function refreshMongodbConfigDraft() {
        root.mongodbConfigDraft = dashboardBridge.activeMongodbConfigContent
        root.mongodbConfigFeedback = ""
    }

    function refreshMongodbRuntimeInfo() {
        root.mongodbRuntimeHomeText = String(dashboardBridge.activeMongodbRuntimeHome || "")
        root.mongodbRuntimeDataDirText = String(dashboardBridge.activeMongodbDataDir || "")
        root.mongodbRuntimeConfigPathText = String(dashboardBridge.activeMongodbConfigPath || "")
        root.mongodbRuntimePortText = String(dashboardBridge.activeMongodbPort || "")
    }

    function refreshMongodbGeneralDraft() {
        var settings = (dashboardBridge && dashboardBridge.mongodbRuntimeSettings) ? dashboardBridge.mongodbRuntimeSettings() : {}
        root.mongodbGeneralBindIpDraft = String(settings.bind_address || "127.0.0.1")
        root.mongodbGeneralBindIpAllDraft = root.mongodbGeneralBindIpDraft !== "127.0.0.1"
        root.mongodbGeneralPortDraft = String((dashboardBridge && dashboardBridge.activeMongodbPort) || "27017")
        root.mongodbGeneralTlsModeDraft = String(settings.tls_mode || "disabled")
        root.mongodbGeneralSystemLogPathDraft = "~/Library/Application Support/Server Engine/logs/mongodb/mongod.log"
        root.mongodbGeneralSystemLogAppendDraft = settings.system_log_append === undefined ? true : Boolean(settings.system_log_append)
        root.mongodbGeneralSystemLogVerbosityDraft = String(settings.system_log_verbosity === undefined ? "0" : settings.system_log_verbosity)
        root.mongodbGeneralForkDraft = false
        root.mongodbGeneralPidFilePathDraft = "~/Library/Application Support/Server Engine/runtime/mongodb/mongod.pid"
        root.mongodbGeneralDbPathDraft = "~/Library/Application Support/Server Engine/data/mongodb"
        root.mongodbGeneralAuthorizationDraft = "disabled"
        root.mongodbGeneralClusterAuthModeDraft = "keyFile"
        root.mongodbGeneralKeyFileDraft = "~/Library/Application Support/Server Engine/config/mongodb/keyfile"
        root.mongodbGeneralJavascriptEnabledDraft = settings.javascript_enabled === undefined ? true : Boolean(settings.javascript_enabled)
        root.mongodbGeneralReplSetNameDraft = "rs0"
    }

    function mongodbBackupFlowTitleText() {
        if (dashboardBridge.mongodbBackupBusy) {
            if (backupFlowAction === "restore") {
                return "Restoring " + root.mongodbBackupDatabaseName
            }
            if (backupFlowAction === "delete") {
                return "Deleting Backup Archive"
            }
            return "Backing Up " + root.mongodbBackupDatabaseName
        }
        if (backupFlowAction === "restore") {
            return "Restore Result"
        }
        if (backupFlowAction === "delete") {
            return "Delete Result"
        }
        return "Backup Result"
    }

    function mongodbImportFlowTitleText() {
        if (dashboardBridge.mongodbImportBusy) {
            return "Importing " + root.mongodbImportDatabaseName
        }
        if (dashboardBridge.mongodbImportError) {
            return "Import Failed"
        }
        return "Import Completed"
    }

    onMongodbBackupDatabaseNameChanged: {
        if (root.mongodbBackupPopupOpen) {
            refreshMongodbBackupItems()
        }
    }

    Component.onCompleted: {
        Qt.callLater(refreshMongodbItems)
    }

    Connections {
        target: dashboardBridge

        function onMongodbRuntimeFeedbackChanged() {
            root.mongodbItemsModel = dashboardBridge.mongodbItems
            if (root.mongodbBackupPopupOpen) {
                root.refreshMongodbBackupItems()
            }
        }

        function onDataChanged() {
            root.refreshMongodbItems()
            if (root.mongodbBackupPopupOpen) {
                root.refreshMongodbBackupItems()
            }
        }
    }

    function mongodbRuntimeSectionDescription(sectionId) {
        switch (sectionId) {
        case "settings":
            return "MongoDB runtime settings for network, logging, process, storage, security, and replication."
        case "configuration":
            return "MongoDB runtime config path and generated config file location."
        case "data.directory":
            return "MongoDB files and runtime data directory used by the active version."
        case "port":
            return "Listen port details for the active MongoDB runtime."
        case "current.status":
            return "Current runtime state and the latest startup or shutdown feedback."
        case "error.log":
            return "Runtime error log output for the active MongoDB database version."
        case "slow.log":
            return "Slow query log controls and output will live here."
        case "binary.log":
            return "Binary log controls and replication-oriented output will live here."
        default:
            return "Manage the active local MongoDB runtime and inspect startup logs."
        }
    }

    function mongodbRuntimeSectionSource(sectionId) {
        switch (sectionId) {
        case "settings":
            return "mongodb_runtime_sections/SettingsSection.qml"
        case "service":
            return "mongodb_runtime_sections/ServiceSection.qml"
        case "configuration":
            return "mongodb_runtime_sections/ConfigFileSection.qml"
        case "data.directory":
            return "mongodb_runtime_sections/StorageLocationSection.qml"
        case "port":
            return "mongodb_runtime_sections/PortSection.qml"
        case "current.status":
            return "mongodb_runtime_sections/CurrentStatusSection.qml"
        case "error.log":
            return "mongodb_runtime_sections/ErrorLogSection.qml"
        case "slow.log":
            return "mongodb_runtime_sections/SlowLogSection.qml"
        default:
            return "mongodb_runtime_sections/PlaceholderSection.qml"
        }
    }

    function mongodbRuntimeSectionLabel(sectionId) {
        for (var i = 0; i < mongodbRuntimePopupSections.length; i++) {
            if (mongodbRuntimePopupSections[i].id === sectionId) {
                return Strings.t(mongodbRuntimePopupSections[i].id)
            }
        }
        return Strings.t(String(sectionId || ""))
    }

    function mongodbRuntimeSectionIcon(sectionId) {
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
                enabled: root.mongodbRunning

                onClicked: root.newMongodbDatabasePopupOpen = true
            }

            Components.AppButton {
                text: Strings.t("root.password")
                iconSource: "icons/lucide/shield.svg"
                enabled: root.mongodbRunning

                onClicked: root.mongodbPasswordPopupOpen = true
            }

            Components.AppButton {
                text: Strings.t("compass")
                iconSource: "icons/lucide/database.svg"
                enabled: false

                onClicked: dashboardBridge.openMongodbCompass()
            }

            Components.AppButton {
                text: Strings.t("cli")
                iconSource: "icons/lucide/terminal.svg"
                enabled: root.databaseRunning

                onClicked: root.databaseCliRequested()
            }

            Components.AppButton {
                text: dashboardBridge.activeMongodbRuntimeBrand
                iconSource: "icons/lucide/settings.svg"

                onClicked: {
                    root.runtimePopupOpen = true
                    root.mongodbRuntimePopupSection = "settings"
                    root.refreshMongodbRuntimeInfo()
                    dashboardBridge.refreshMongodbRuntime()
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Components.AppTextField {
                id: mongodbFilterField
                width: 320
                placeholderText: Strings.t("database.name")

                selectByMouse: true
                inputMethodHints: Qt.ImhNoPredictiveText
            }

            Components.QuickActionButton {
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: "Reload"
                onClicked: {
                    root.refreshMongodbItems()
                    root.refreshMongodbRuntimeInfo()
                    dashboardBridge.refreshMongodbRuntime()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                anchors.fill: parent
                visible: root.mongodbRunning

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
                                model: root.filteredMongodbItemsModel
                                visible: count > 0
                                interactive: false
                                clip: true

                                delegate: Column {
                                    required property int index
                                    width: ListView.view.width
                                    property var mongodbItem: root.filteredMongodbItemsModel[index]

                                    Components.DatabaseRow {
                                        width: parent.width
                                        height: 72
                                        rowData: parent.mongodbItem
                                        onBackupRequested: function(rowData) {
                                            root.backupRequested(rowData)
                                        }
                                        onImportRequested: function(rowData) {
                                            root.mongodbImportDatabaseName = rowData.name
                                            root.mongodbImportPopupOpen = true
                                            dashboardBridge.clearMongodbRuntimeFeedback()
                                        }
                                        onDropRequested: function(rowData) {
                                            root.mongodbDropDatabaseName = rowData.name
                                            root.mongodbDropConfirmOpen = true
                                            dashboardBridge.clearMongodbRuntimeFeedback()
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
                            visible: root.filteredMongodbItemsModel.length === 0
                            spacing: 10

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.mongodbFilterText.length > 0 ? "No matching MongoDB databases" : "No MongoDB databases detected"
                                color: Theme.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.mongodbFilterText.length > 0
                                    ? "Try a different database name keyword."
                                    : "This page lists real MongoDB databases from the active local MongoDB runtime when it is reachable."
                                color: Theme.muted
                                font.pixelSize: 14
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                visible: !root.mongodbRunning
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Strings.t("mongodb.runtime.is.not.running")
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

    MongoDropConfirmDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoImportDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoImportResultDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoBackupDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoBackupActionConfirmDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoBackupResultDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoPasswordDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoNewDatabaseDialog {
        root: root
        dashboardBridge: dashboardBridge
    }

    MongoRuntimeDialog {
        root: root
        dashboardBridge: dashboardBridge
    }
}
