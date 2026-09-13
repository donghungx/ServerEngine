import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    property var draft: ({})
    property bool restartConfirmOpen: false
    property string feedbackText: ""
    property bool feedbackError: false

    function loadSettings() {
        if (!dashboardBridge) {
            return
        }
        draft = dashboardBridge.databaseOptimizationSettings()
    }

    function asInt(value, fallback) {
        var n = parseInt(String(value), 10)
        return isNaN(n) ? fallback : n
    }

    function maxRamMb() {
        var connections = asInt(draft.max_connections, 160)
        var fixedMb = asInt(draft.key_buffer_size_mb, 16)
            + asInt(draft.tmp_table_size_mb, 128)
            + asInt(draft.innodb_buffer_pool_size_mb, 1024)
            + asInt(draft.innodb_log_buffer_size_mb, 128)
        if (dashboardBridge && dashboardBridge.supportsDatabaseQueryCache) {
            fixedMb += asInt(draft.query_cache_size_mb, 64)
        }
        var perConnKb = asInt(draft.sort_buffer_size_kb, 256)
            + asInt(draft.read_buffer_size_kb, 256)
            + asInt(draft.read_rnd_buffer_size_kb, 256)
            + asInt(draft.join_buffer_size_kb, 256)
            + asInt(draft.thread_stack_kb, 256)
            + asInt(draft.binlog_cache_size_kb, 64)
        return (fixedMb + ((perConnKb * connections) / 1024.0)).toFixed(1)
    }

    Component.onCompleted: loadSettings()
    onDashboardBridgeChanged: loadSettings()

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("optimization")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("tune.active.database.runtime.memory.and.cache.settings")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: 10
                Text { text: Strings.t("optimization.plan"); color: Theme.text; font.pixelSize: 14; anchors.verticalCenter: planCombo.verticalCenter }
                Components.AppComboBox {
                    id: planCombo
                    width: 220
                    model: ["Custom", "2-4GB", "4-8GB", "8-16GB", "16GB+"]
                    onActivated: {
                        if (currentText === "2-4GB") {
                            draft.key_buffer_size_mb = 16; draft.tmp_table_size_mb = 128
                            if (dashboardBridge && dashboardBridge.supportsDatabaseQueryCache) {
                                draft.query_cache_size_mb = 64
                            }
                            draft.innodb_buffer_pool_size_mb = 768; draft.innodb_log_buffer_size_mb = 64
                            draft.sort_buffer_size_kb = 256; draft.read_buffer_size_kb = 256; draft.read_rnd_buffer_size_kb = 256
                            draft.join_buffer_size_kb = 256; draft.thread_stack_kb = 256; draft.binlog_cache_size_kb = 64
                            draft.thread_cache_size = 64; draft.table_open_cache = 1024; draft.max_connections = 120
                        } else if (currentText === "4-8GB") {
                            draft.innodb_buffer_pool_size_mb = 1024; draft.innodb_log_buffer_size_mb = 128
                            draft.max_connections = 160; draft.table_open_cache = 1400; draft.thread_cache_size = 96
                        } else if (currentText === "8-16GB") {
                            draft.innodb_buffer_pool_size_mb = 2048; draft.max_connections = 240; draft.table_open_cache = 2048
                        } else if (currentText === "16GB+") {
                            draft.innodb_buffer_pool_size_mb = 4096; draft.max_connections = 320; draft.table_open_cache = 2048
                        }
                        draft = Object.assign({}, draft)
                    }
                }
                Text { text: Strings.t("max.ram.usage"); color: Theme.text; font.pixelSize: 14; anchors.verticalCenter: ramField.verticalCenter }
                Components.AppTextField { id: ramField; width: 140; readOnly: true; text: maxRamMb() }
                Text { text: Strings.t("mb"); color: Theme.muted; font.pixelSize: 14; anchors.verticalCenter: ramField.verticalCenter }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            Components.AppScrollArea {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clipContent: true

                RowLayout {
                    width: parent.width
                    spacing: 18

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        columns: 3
                        columnSpacing: 12
                        rowSpacing: 8

                        Text { text: Strings.t("key.buffer.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.key_buffer_size_mb, 16))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.key_buffer_size_mb = root.asInt(text, 16)
                        }
                        Text { text: Strings.t("mb"); color: Theme.muted; font.pixelSize: 12 }

                        Text {
                            visible: dashboardBridge && dashboardBridge.supportsDatabaseQueryCache
                            text: Strings.t("query.cache.size")
                            color: Theme.text
                            font.pixelSize: 12
                        }
                        Components.AppTextField {
                            visible: dashboardBridge && dashboardBridge.supportsDatabaseQueryCache
                            Layout.fillWidth: true
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            text: String(root.asInt(draft.query_cache_size_mb, 64))
                            onTextChanged: draft.query_cache_size_mb = root.asInt(text, 64)
                        }
                        Text {
                            visible: dashboardBridge && dashboardBridge.supportsDatabaseQueryCache
                            text: Strings.t("mb")
                            color: Theme.muted
                            font.pixelSize: 12
                        }

                        Text { text: Strings.t("tmp.table.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.tmp_table_size_mb, 128))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.tmp_table_size_mb = root.asInt(text, 128)
                        }
                        Text { text: Strings.t("mb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("innodb.buffer.pool.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.innodb_buffer_pool_size_mb, 1024))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.innodb_buffer_pool_size_mb = root.asInt(text, 1024)
                        }
                        Text { text: Strings.t("mb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("innodb.log.buffer.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.innodb_log_buffer_size_mb, 128))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.innodb_log_buffer_size_mb = root.asInt(text, 128)
                        }
                        Text { text: Strings.t("mb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("sort.buffer.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.sort_buffer_size_kb, 256))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.sort_buffer_size_kb = root.asInt(text, 256)
                        }
                        Text { text: Strings.t("kb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("read.buffer.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.read_buffer_size_kb, 256))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.read_buffer_size_kb = root.asInt(text, 256)
                        }
                        Text { text: Strings.t("kb"); color: Theme.muted; font.pixelSize: 12 }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        columns: 3
                        columnSpacing: 12
                        rowSpacing: 8

                        Text { text: Strings.t("read.rnd.buffer.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.read_rnd_buffer_size_kb, 256))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.read_rnd_buffer_size_kb = root.asInt(text, 256)
                        }
                        Text { text: Strings.t("kb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("join.buffer.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.join_buffer_size_kb, 256))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.join_buffer_size_kb = root.asInt(text, 256)
                        }
                        Text { text: Strings.t("kb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("thread.stack"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.thread_stack_kb, 256))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.thread_stack_kb = root.asInt(text, 256)
                        }
                        Text { text: Strings.t("kb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("binlog.cache.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.binlog_cache_size_kb, 64))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.binlog_cache_size_kb = root.asInt(text, 64)
                        }
                        Text { text: Strings.t("kb"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("thread.cache.size"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.thread_cache_size, 96))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.thread_cache_size = root.asInt(text, 96)
                        }
                        Text { text: Strings.t("count"); color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("table.open.cache"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.table_open_cache, 1400))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.table_open_cache = root.asInt(text, 1400)
                        }
                        Text { text: "<= 2048"; color: Theme.muted; font.pixelSize: 12 }

                        Text { text: Strings.t("max.connections"); color: Theme.text; font.pixelSize: 12 }
                        Components.AppTextField {
                            Layout.fillWidth: true
                            text: String(root.asInt(draft.max_connections, 160))
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: draft.max_connections = root.asInt(text, 160)
                        }
                        Text { text: Strings.t("count"); color: Theme.muted; font.pixelSize: 12 }
                    }
                }
            }
        }

        footerLeft: Text {
            text: feedbackText
            color: feedbackError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Text {
                text: Strings.t("restart.database.for.the.configuration.to.take.effect")
                color: Theme.muted
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
            Components.AppButton {
                text: Strings.t("restart.mysql.service")
                onClicked: dashboardBridge.restartDatabaseRuntime()
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var ok = dashboardBridge.saveDatabaseOptimizationSettings(draft)
                    feedbackText = dashboardBridge.databaseRuntimeMessage
                    feedbackError = !ok
                    if (ok && pageRoot.databaseRunning) {
                        restartConfirmOpen = true
                    }
                }
            }
        }
    }

    Window {
        id: restartConfirmWindow
        visible: restartConfirmOpen
        width: 500
        height: 190
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: Strings.t("restart.database.runtime")
        modality: Qt.ApplicationModal
        transientParent: runtimeWindow
        flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        x: runtimeWindow ? runtimeWindow.x + Math.round((runtimeWindow.width - width) / 2) : 0
        y: runtimeWindow ? runtimeWindow.y + Math.round((runtimeWindow.height - height) / 2) : 0
        onVisibleChanged: if (!visible) restartConfirmOpen = false
        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 16
                spacing: 14
                Label { Layout.fillWidth: true; text: Strings.t("database.runtime.is.running.restart.now.to.apply.optimization.changes"); color: Theme.text; wrapMode: Text.WordWrap; font.pixelSize: 14 }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Components.AppButton { text: Strings.t("later"); onClicked: restartConfirmOpen = false }
                    Components.AppButton { text: Strings.t("restart"); highlighted: true; textColor: "white"; onClicked: { restartConfirmOpen = false; dashboardBridge.restartDatabaseRuntime() } }
                }
            }
        }
    }
}


