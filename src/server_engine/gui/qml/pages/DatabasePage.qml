import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    signal databaseCliRequested()
    signal backupRequested(var rowData)

    required property var dashboardBridge
    border.width: 0
    color: "transparent"
    readonly property bool databaseRunning: String(dashboardBridge.activeDatabaseServiceState || "").toLowerCase() === "running"
    property bool runtimePopupOpen: false
    property bool newDatabasePopupOpen: false
    property bool rootPasswordPopupOpen: false
    property bool importPopupOpen: false
    property bool importClearExisting: false
    property bool dropConfirmOpen: false
    property string importDatabaseName: ""
    property string dropDatabaseName: ""
    property string rootPasswordFeedback: ""
    property bool rootPasswordFeedbackError: false
    property string databaseConfigDraft: ""
    property string databaseConfigFeedback: ""
    property var databaseItemsModel: []
    readonly property string databaseFilterText: databaseFilterField ? String(databaseFilterField.text || "").trim().toLowerCase() : ""
    readonly property var filteredDatabaseItemsModel: {
        if (databaseFilterText.length === 0) {
            return databaseItemsModel
        }
        return databaseItemsModel.filter(function(item) {
            var nameValue = String(item.name || "").toLowerCase()
            var typeValue = String(item.type || "").toLowerCase()
            return nameValue.indexOf(databaseFilterText) !== -1 || typeValue.indexOf(databaseFilterText) !== -1
        })
    }
    property var databaseCharsets: [
        "utf8mb4",
        "utf8",
        "latin1",
        "ascii",
        "big5",
        "binary",
        "cp1250",
        "cp1251",
        "cp1256",
        "cp1257",
        "cp850",
        "cp852",
        "cp866",
        "cp932",
        "dec8",
        "eucjpms",
        "euckr",
        "gb18030",
        "gb2312",
        "gbk",
        "geostd8",
        "greek",
        "hebrew",
        "hp8",
        "keybcs2",
        "koi8r",
        "koi8u",
        "latin2",
        "latin5",
        "latin7",
        "macce",
        "macroman",
        "sjis",
        "swe7",
        "tis620",
        "ucs2",
        "ujis",
        "utf16",
        "utf16le",
        "utf32"
    ]
    property bool slowLogEnabled: false
    property string slowLogLongQueryTime: "3"
    property string slowLogNotUsingIndexes: "On"
    property string databaseRuntimeBindAddressDraft: "127.0.0.1"
    property string databaseRuntimeTimeZoneDraft: "UTC"
    property string databaseRuntimeWaitTimeoutDraft: "900"
    property string databaseRuntimeInteractiveTimeoutDraft: "900"
    property bool databaseRuntimeLogQueriesNotUsingIndexesDraft: false
    property bool databaseRuntimeLogSlowAdminStatementsDraft: false
    property bool databaseRuntimeLogSlowExtraDraft: false
    property string databaseRuntimeLogThrottleQueriesNotUsingIndexesDraft: "0"
    property string runtimePopupSection: "settings"
    property var runtimePopupSections: [
        { id: "settings", label: Strings.t("settings") },
        { id: "service", label: Strings.t("service") },
        { id: "configuration", label: Strings.t("configuration") },
        { id: "data.directory", label: Strings.t("data.directory") },
        { id: "port", label: Strings.t("port") },
        { id: "error.log", label: Strings.t("error.log") }
    ]

    function folderUrl(path) {
        return "file://" + encodeURI(path)
    }

    function refreshDatabaseItems() {
        root.databaseItemsModel = dashboardBridge.databaseItems
    }

    function databaseIndex(databaseName) {
        for (var i = 0; i < root.databaseItemsModel.length; i++) {
            if (String(root.databaseItemsModel[i].name || "") === String(databaseName || "")) {
                return i
            }
        }
        return root.databaseItemsModel.length > 0 ? 0 : -1
    }

    function refreshDatabaseConfigDraft() {
        root.databaseConfigDraft = dashboardBridge.activeDatabaseConfigContent
        root.databaseConfigFeedback = ""
    }

    function refreshDatabaseRuntimeSettingsDraft() {
        var settings = dashboardBridge.databaseRuntimeSettings ? dashboardBridge.databaseRuntimeSettings() : {}
        root.databaseRuntimeBindAddressDraft = String(settings.bind_address || "127.0.0.1")
        root.databaseRuntimeTimeZoneDraft = String(settings.time_zone || "UTC")
        root.databaseRuntimeWaitTimeoutDraft = String(settings.wait_timeout || "900")
        root.databaseRuntimeInteractiveTimeoutDraft = String(settings.interactive_timeout || "900")
        root.databaseRuntimeLogQueriesNotUsingIndexesDraft = Boolean(settings.log_queries_not_using_indexes)
        root.databaseRuntimeLogSlowAdminStatementsDraft = Boolean(settings.log_slow_admin_statements)
        root.databaseRuntimeLogSlowExtraDraft = Boolean(settings.log_slow_extra)
        root.databaseRuntimeLogThrottleQueriesNotUsingIndexesDraft = String(settings.log_throttle_queries_not_using_indexes || "0")
    }

    function importFlowTitleText() {
        if (dashboardBridge.databaseImportBusy) {
            return "Import SQL into " + root.importDatabaseName
        }
        if (dashboardBridge.databaseImportError) {
            return Strings.t("import.failed")
        }
        return Strings.t("import.completed")
    }

    Component.onCompleted: {
        if (root.databaseRunning) {
            root.refreshDatabaseItems()
        }
    }

    onDatabaseRunningChanged: {
        if (root.databaseRunning && root.databaseItemsModel.length === 0) {
            root.refreshDatabaseItems()
        }
    }

    Connections {
        target: dashboardBridge

    }

    function runtimeSectionDescription(sectionLabel) {
        switch (sectionLabel) {
        case "settings":
            return "MySQL and MariaDB runtime settings for connection access, idle timeouts, and slow-query debug controls."
        case "configuration":
            return Strings.t("database.runtime.config.path.and.generated.config.file.location")
        case "data.directory":
            return "Database files and runtime data directory used by the active version."
        case "port":
            return Strings.t("listen.port.details.for.the.active.database.runtime")
        case "current.status":
            return Strings.t("current.runtime.state.and.the.latest.startup.or.shutdown.feedback")
        case "optimization":
            return Strings.t("database.optimization.tuning.options.will.live.here")
        case "error.log":
            return Strings.t("runtime.error.log.output.for.the.active.database.version")
        case "slow.log":
            return Strings.t("slow.query.log.controls.and.output.will.live.here")
        case "binary.log":
            return Strings.t("binary.log.controls.and.replication.oriented.output.will.live.here")
        default:
            return Strings.t("manage.the.active.local.database.runtime.and.inspect.startup.logs")
        }
    }

    function databaseRuntimeSectionSource(sectionLabel) {
        switch (sectionLabel) {
        case "settings":
            return "database_runtime_sections/SettingsSection.qml"
        case "service":
            return "database_runtime_sections/ServiceSection.qml"
        case "configuration":
            return "database_runtime_sections/ConfigFileSection.qml"
        case "data.directory":
            return "database_runtime_sections/StorageLocationSection.qml"
        case "port":
            return "database_runtime_sections/PortSection.qml"
        case "current.status":
            return "database_runtime_sections/CurrentStatusSection.qml"
        case "error.log":
            return "database_runtime_sections/ErrorLogSection.qml"
        case "slow.log":
            return "database_runtime_sections/SlowLogSection.qml"
        case "optimization":
            return "database_runtime_sections/OptimizationSection.qml"
        default:
            return "database_runtime_sections/PlaceholderSection.qml"
        }
    }

    function runtimeSectionIcon(sectionLabel) {
        switch (sectionLabel) {
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
        case "optimization":
            return "server"
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
                enabled: root.databaseRunning

                onClicked: root.newDatabasePopupOpen = true
            }

            Components.AppButton {
                text: Strings.t("root.password")
                iconSource: "icons/lucide/shield.svg"
                enabled: root.databaseRunning

                onClicked: root.rootPasswordPopupOpen = true
            }

            Components.AppButton {
                text: dashboardBridge.phpMyAdminBusy ? "Opening..." : "phpMyAdmin"
                iconSource: "icons/lucide/phpmyadmin.svg"
                enabled: root.databaseRunning && !dashboardBridge.phpMyAdminBusy

                onClicked: dashboardBridge.openPhpMyAdmin()
            }

            Components.AppButton {
                text: Strings.t("cli")
                iconSource: "icons/lucide/terminal.svg"
                enabled: root.databaseRunning

                onClicked: root.databaseCliRequested()
            }

            Components.AppButton {
                text: dashboardBridge.activeDatabaseRuntimeBrand
                iconSource: "icons/lucide/settings.svg"

                onClicked: {
                    root.runtimePopupOpen = true
                    root.runtimePopupSection = "settings"
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Components.AppTextField {
                id: databaseFilterField
                width: 320
                placeholderText: Strings.t("database.name")

                selectByMouse: true
                inputMethodHints: Qt.ImhNoPredictiveText
            }

            Components.QuickActionButton {
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: Strings.t("reload")
                onClicked: dashboardBridge.refreshDatabaseRuntime()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                anchors.fill: parent
                visible: root.databaseRunning

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

                            Components.HeaderCell { label: Strings.t("database.name"); cellWidth: 366 }
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
                                model: root.filteredDatabaseItemsModel
                                visible: count > 0
                                interactive: false
                                clip: true

                                delegate: Column {
                                    required property int index
                                    width: ListView.view.width
                                    property var databaseItem: root.filteredDatabaseItemsModel[index]

                                    Components.DatabaseRow {
                                        width: parent.width
                                        height: 72
                                        rowData: parent.databaseItem
                                        onBackupRequested: function(rowData) {
                                            root.backupRequested(rowData)
                                        }
                                        onImportRequested: function(rowData) {
                                            root.importDatabaseName = rowData.name
                                            root.importPopupOpen = true
                                            dashboardBridge.clearDatabaseRuntimeFeedback()
                                        }
                                        onDropRequested: function(rowData) {
                                            root.dropDatabaseName = rowData.name
                                            root.dropConfirmOpen = true
                                            dashboardBridge.clearDatabaseRuntimeFeedback()
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
                            visible: root.filteredDatabaseItemsModel.length === 0
                            spacing: 10

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.databaseFilterText.length > 0 ? "No matching databases" : "No databases detected"
                                color: Theme.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.databaseFilterText.length > 0
                                    ? "Try a different database name keyword."
                                    : "This page lists real databases from the active local database runtime when it is reachable."
                                color: Theme.muted
                                font.pixelSize: 14
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                visible: !root.databaseRunning
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Strings.t("database.runtime.is.not.running")
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

    Window {
        id: dropConfirmWindow
        visible: root.dropConfirmOpen
        width: 400
        height: 108
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("confirm.drop.database")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root.Window.window
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (!visible) {
                root.dropConfirmOpen = false
                root.dropDatabaseName = ""
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("drop.database")
            moveWindow: dropConfirmWindow
            color: Theme.surface

            ColumnLayout {
                id: dropConfirmContent
                anchors.fill: parent
                spacing: 12

                Text {
                    text: Strings.t("this.will.permanently.delete") + root.dropDatabaseName + "'. This action cannot be undone."
                    color: Theme.text
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.weight: Font.Normal
                }

                Text {
                    text: dashboardBridge.databaseRuntimeMessage
                    color: dashboardBridge.databaseRuntimeError ? Theme.danger : Theme.success
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: dashboardBridge.databaseRuntimeMessage.length > 0
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            footerRight: Row {
                spacing: 8

                Components.AppButton {
                    text: Strings.t("cancel")
                    enabled: !dashboardBridge.databaseActionBusy
                    onClicked: root.dropConfirmOpen = false
                }

                Components.AppButton {
                    text: Strings.t("drop")
                    highlighted: true
                    enabled: !dashboardBridge.databaseActionBusy
                        && root.dropDatabaseName.length > 0
                    onClicked: {
                        var ok = dashboardBridge.dropDatabase(root.dropDatabaseName)
                        if (ok) {
                            root.dropConfirmOpen = false
                            root.refreshDatabaseItems()
                        }
                    }
                }
            }
        }
    }

    Window {
        id: importWindow
        visible: root.importPopupOpen
        width: 400
        height: 156
        minimumWidth: width
        maximumWidth: width

        minimumHeight: 156
        maximumHeight: 188
        title: root.importDatabaseName.length > 0 ? ("Import into " + root.importDatabaseName) : "Database Import"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root.Window.window
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint

        function updateImportWindowHeight() {
            height = root.importClearExisting ? 188 : 156
        }

        onVisibleChanged: {
            if (visible) {
                dashboardBridge.clearDatabaseRuntimeFeedback()
                root.importClearExisting = false
                if (importClearExistingCheck) {
                    importClearExistingCheck.checked = false
                }
                updateImportWindowHeight()
            } else {
                dashboardBridge.clearDatabaseImportSelection()
                root.importPopupOpen = false
                root.importDatabaseName = ""
                root.importClearExisting = false
                if (importClearExistingCheck) {
                    importClearExistingCheck.checked = false
                }
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("database.import")
            moveWindow: importWindow
            color: Theme.surface

            ColumnLayout {
                Layout.fillWidth: true
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 12

                Label {
                    text: root.importDatabaseName.length > 0
                        ? "Import a SQL file or archive into " + root.importDatabaseName + ". Supported formats: .sql, .zip, .tar.gz, .tgz, .gz."
                        : "Import a SQL file or archive."
                    color: Theme.text
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Components.AppTextField {
                        Layout.fillWidth: true
                        text: dashboardBridge.databaseImportSelectedPath.length > 0
                            ? dashboardBridge.databaseImportSelectedPath
                            : ""

                        placeholderText: Strings.t("choose.import.file")
                        readOnly: true
                        selectByMouse: true
                    }

                    Row {
                        spacing: 4

                        Components.AppButton {
                            text: Strings.t("choose.file")
                            enabled: !dashboardBridge.databaseImportBusy

                            onClicked: dashboardBridge.chooseDatabaseImportFile()
                        }
                    }
                }

                Text {
                    visible: root.importClearExisting
                    text: "All existing tables and data in this database will be permanently removed before import. This cannot be undone."
                    color: Theme.danger
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            footerLeft: Components.AppCheckBox {
                id: importClearExistingCheck
                text: "Clear existing data"
                checked: root.importClearExisting

                onToggled: function(checked) {
                    root.importClearExisting = checked
                    importWindow.updateImportWindowHeight()
                }
            }

            footerRight: Row {
                Components.AppButton {
                    height: 24
                    text: dashboardBridge.databaseImportBusy ? "Importing..." : "Import"
                    highlighted: true
                    textColor: "white"

                    enabled: !dashboardBridge.databaseImportBusy
                        && dashboardBridge.databaseImportSelectedPath.length > 0
                        && root.importDatabaseName.length > 0

                    onClicked: {
                        dashboardBridge.clearDatabaseRuntimeFeedback()
                        var ok = dashboardBridge.importDatabaseFile(
                            root.importDatabaseName,
                            dashboardBridge.databaseImportSelectedPath,
                            root.importClearExisting
                        )
                        if (ok) {
                            root.importPopupOpen = false
                        }
                    }
                }
            }
        }
    }

    Window {
        id: databaseRuntimeWindow
        visible: root.runtimePopupOpen
        width: 720
        height: 620
        minimumWidth: width
        maximumWidth: width
        minimumHeight: 400
        maximumHeight: 820
        title: dashboardBridge.activeDatabaseRuntimeLabel + " Runtime"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root.Window.window
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        function applyRuntimeWindowHeight(sectionId) {
            var nextHeight = 620
            switch (String(sectionId || "")) {
            case "service":
                nextHeight = 400
                break
            case "configuration":
                nextHeight = 560
                break
            case "data.directory":
                nextHeight = 500
                break
            case "port":
                nextHeight = 500
                break
            case "error.log":
                nextHeight = 640
                break
            case "settings":
            default:
                nextHeight = 620
                break
            }
            nextHeight = Math.max(minimumHeight, Math.min(maximumHeight, nextHeight))
            if (height !== nextHeight) {
                height = nextHeight
            }
        }

        Timer {
            id: databaseRuntimeRefreshTimer
            interval: 150
            repeat: false
            onTriggered: {
                if (!databaseRuntimeWindow.visible) {
                    return
                }
                dashboardBridge.refreshDatabaseRuntime()
            }
        }

        onVisibleChanged: {
            if (visible) {
                root.refreshDatabaseConfigDraft()
                root.refreshDatabaseRuntimeSettingsDraft()
                databaseRuntimeRefreshTimer.restart()
                Qt.callLater(function() {
                    applyRuntimeWindowHeight(root.runtimePopupSection)
                })
            } else {
                databaseRuntimeRefreshTimer.stop()
                root.runtimePopupOpen = false
            }
        }

        Components.PageWindowFrame {
            moveWindow: databaseRuntimeWindow
            bodyMargins: 16

            headerContent: Item {
                anchors.fill: parent

                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 8
                    text: Strings.t(root.runtimePopupSection)
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Item {
                    anchors.fill: parent
                    anchors.topMargin: 28
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.bottomMargin: 6
                    clip: true

                    Row {
                        height: 58
                        spacing: 6

                        Repeater {
                            model: root.runtimePopupSections

                            delegate: Components.TopIconTab {
                                id: runtimeTopTabItem
                                required property int index
                                property var navItem: root.runtimePopupSections[index]
                                selected: root.runtimePopupSection === navItem.id
                                label: runtimeTopTabItem.navItem.label
                                iconSource: "../icons/lucide/" + root.runtimeSectionIcon(runtimeTopTabItem.navItem.id) + ".svg"
                                onClicked: {
                                    root.runtimePopupSection = runtimeTopTabItem.navItem.id
                                    if (runtimeTopTabItem.navItem.id === "configuration") {
                                        root.refreshDatabaseConfigDraft()
                                    } else if (runtimeTopTabItem.navItem.id === "settings") {
                                        root.refreshDatabaseRuntimeSettingsDraft()
                                    }
                                    databaseRuntimeWindow.applyRuntimeWindowHeight(runtimeTopTabItem.navItem.id)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 20

                Loader {
                    id: databaseRuntimeSectionLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    source: root.databaseRuntimeSectionSource(root.runtimePopupSection)
                    onLoaded: {
                        if (item) {
                            item.pageRoot = root
                            item.dashboardBridge = dashboardBridge
                            item.runtimeWindow = databaseRuntimeWindow
                        }
                        Qt.callLater(function() {
                            databaseRuntimeWindow.applyRuntimeWindowHeight(root.runtimePopupSection)
                        })
                    }
                }
            }
        }
    }

    Window {
        id: rootPasswordWindow
        visible: root.rootPasswordPopupOpen
        width: 400
        height: 160
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("root.password")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root.Window.window

        flags: Qt.Dialog
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (visible) {
                rootPasswordInput.text = dashboardBridge.databaseRootPassword
                root.rootPasswordFeedback = ""
                root.rootPasswordFeedbackError = false
                dashboardBridge.clearDatabaseRuntimeFeedback()
            } else {
                root.rootPasswordPopupOpen = false
                rootPasswordInput.text = ""
                root.rootPasswordFeedback = ""
                root.rootPasswordFeedbackError = false
                dashboardBridge.clearDatabaseRuntimeFeedback()
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("root.password")
            moveWindow: rootPasswordWindow
            color: Theme.surface

            ColumnLayout {
                id: rootPasswordContent
                anchors.fill: parent
                spacing: 12

                Label {
                    text: Strings.t("review.the.current.stored.root.password.and.optionally.change.it.for.the.active")
                        + dashboardBridge.activeDatabaseRuntimeLabel
                        + " runtime."
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Components.AppTextField {
                    id: rootPasswordInput
                    Layout.fillWidth: true
                    placeholderText: Strings.t("root.password")
                    echoMode: TextInput.Normal
                }

                Label {
                    visible: text.length > 0

                    text: root.rootPasswordFeedback.length > 0
                        ? root.rootPasswordFeedback
                        : dashboardBridge.databaseRuntimeMessage

                    color: root.rootPasswordFeedback.length > 0
                        ? (root.rootPasswordFeedbackError ? "#bb4d4d" : "#4aa94b")
                        : (dashboardBridge.databaseRuntimeError ? "#bb4d4d" : "#4aa94b")

                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            footerRight: Row {
                spacing: 8

                Components.AppButton {
                    text: Strings.t("cancel")

                    onClicked: root.rootPasswordPopupOpen = false
                }

                Components.AppButton {
                    text: Strings.t("settings.appearance.save")
                    highlighted: true
                    textColor: "white"

                    onClicked: {
                        if (rootPasswordInput.text.length === 0) {
                            root.rootPasswordFeedback = "Root password is required."
                            root.rootPasswordFeedbackError = true
                        } else if (dashboardBridge.updateDatabaseRootPassword(rootPasswordInput.text)) {
                            root.rootPasswordFeedback = ""
                            root.rootPasswordFeedbackError = false
                            rootPasswordInput.text = ""
                            root.rootPasswordPopupOpen = false
                            dashboardBridge.refreshDatabaseRuntime()
                        } else {
                            root.rootPasswordFeedback = ""
                            root.rootPasswordFeedbackError = false
                        }
                    }
                }
            }
        }
    }
    Window {
        id: newDatabaseWindow
        visible: root.newDatabasePopupOpen
        width: 480
        height: 144
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("new.database")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root.Window.window

        flags: Qt.Dialog
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        property bool submitLocked: false

        onVisibleChanged: {
            if (visible) {
                submitLocked = false
                databaseNameInput.text = ""
                charsetCombo.currentIndex = 0
                dashboardBridge.clearDatabaseRuntimeFeedback()
                Qt.callLater(function() {
                    databaseNameInput.forceActiveFocus()
                })
            } else {
                root.newDatabasePopupOpen = false
                submitLocked = false
                databaseNameInput.text = ""
                charsetCombo.currentIndex = 0
                dashboardBridge.clearDatabaseRuntimeFeedback()
            }
        }

        function createDatabaseFromDialog() {
            if (submitLocked) {
                return
            }

            submitLocked = true
            if (
                dashboardBridge.createDatabase(
                    databaseNameInput.text,
                    charsetCombo.currentText
                )
            ) {
                databaseNameInput.text = ""
                charsetCombo.currentIndex = 0
                root.newDatabasePopupOpen = false
                root.refreshDatabaseItems()
                dashboardBridge.refreshDatabaseRuntime()
            } else {
                submitLocked = false
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("new.database")
            moveWindow: newDatabaseWindow
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                Label {
                    text: Strings.t("create.a.new.database.in.the.active")
                        + dashboardBridge.activeDatabaseRuntimeLabel
                        + " runtime."
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Components.AppTextField {
                        id: databaseNameInput
                        Layout.fillWidth: true
                        placeholderText: Strings.t("database.name")
                        enabled: !newDatabaseWindow.submitLocked

                        onAccepted: confirmButton.triggerClick()
                    }

                    Components.AppComboBox {
                        id: charsetCombo
                        Layout.preferredWidth: 108
                        model: root.databaseCharsets
                        enabled: !newDatabaseWindow.submitLocked
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            footerLeft: Text {
                visible: text.length > 0

                text: dashboardBridge.databaseRuntimeMessage

                color: dashboardBridge.databaseRuntimeError
                    ? Theme.danger
                    : Theme.success

                width: parent ? parent.width : 0
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
                clip: true
            }

            footerRight: Row {
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                Components.AppButton {
                    text: Strings.t("cancel")

                    onClicked: root.newDatabasePopupOpen = false
                }

                Components.AppButton {
                    id: confirmButton
                    text: Strings.t("confirm")

                    highlighted: true
                    textColor: "white"
                    enabled: !newDatabaseWindow.submitLocked

                    onClicked: newDatabaseWindow.createDatabaseFromDialog()
                }
            }
        }
    }
}
