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
    property string feedbackText: ""
    property bool feedbackError: false

    function indexForValue(model, value, fallbackIndex) {
        var target = String(value || "")
        for (var i = 0; i < (model ? model.length : 0); i++) {
            var item = model[i]
            var itemValue = String((item && item.value !== undefined) ? item.value : item)
            if (itemValue === target) {
                return i
            }
        }
        return fallbackIndex
    }

    function loadSettings() {
        if (pageRoot && dashboardBridge && dashboardBridge.databaseRuntimeSettings) {
            pageRoot.refreshDatabaseRuntimeSettingsDraft()
        }
    }

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    function resetSettings() {
        if (!pageRoot) {
            return
        }
        pageRoot.databaseRuntimeBindAddressDraft = "127.0.0.1"
        pageRoot.databaseRuntimeTimeZoneDraft = "UTC"
        pageRoot.databaseRuntimeWaitTimeoutDraft = "900"
        pageRoot.databaseRuntimeInteractiveTimeoutDraft = "900"
        pageRoot.databaseRuntimeLogQueriesNotUsingIndexesDraft = false
        pageRoot.databaseRuntimeLogSlowAdminStatementsDraft = false
        pageRoot.databaseRuntimeLogSlowExtraDraft = false
        pageRoot.databaseRuntimeLogThrottleQueriesNotUsingIndexesDraft = "0"
        if (accessModeGroup) {
            accessModeGroup.selectedValue = "127.0.0.1"
        }
        if (waitTimeoutCombo) {
            waitTimeoutCombo.currentIndex = 2
        }
        if (interactiveTimeoutCombo) {
            interactiveTimeoutCombo.currentIndex = 1
        }
        if (logQueriesCombo) {
            logQueriesCombo.currentIndex = 0
        }
        if (logSlowAdminCombo) {
            logSlowAdminCombo.currentIndex = 0
        }
        if (logSlowExtraCombo) {
            logSlowExtraCombo.currentIndex = 0
        }
        if (logThrottleCombo) {
            logThrottleCombo.currentIndex = 0
        }
        if (saveButton) {
            saveButton.successActive = false
        }
    }

    onPageRootChanged: loadSettings()
    onDashboardBridgeChanged: loadSettings()

    Connections {
        target: mainWindow()
        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "database.restart_after_runtime_save") {
                if (dashboardBridge && dashboardBridge.restartDatabaseRuntime) {
                    dashboardBridge.restartDatabaseRuntime()
                }
            }
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Components.SettingsRadioGroup {
                id: accessModeGroup
                title: "Allow access"
                description: "Choose whether the database only accepts local connections or listens on all interfaces."
                selectedValue: pageRoot ? pageRoot.databaseRuntimeBindAddressDraft : "127.0.0.1"
                model: [
                    { label: "Local only", value: "127.0.0.1" },
                    { label: "All interfaces", value: "0.0.0.0" }
                ]
                onSelected: function(nextValue) {
                    if (pageRoot) {
                        pageRoot.databaseRuntimeBindAddressDraft = String(nextValue || "127.0.0.1")
                    }
                }
            }

            Components.TimezoneSetting {
                dashboardBridge: dashboardBridge
                title: "Default time zone"
                description: "Choose the server time zone used for timestamps and conversions."
                selectedValue: pageRoot ? pageRoot.databaseRuntimeTimeZoneDraft : "UTC"
                onSelectedValuePicked: function(nextValue) {
                    if (pageRoot) {
                        pageRoot.databaseRuntimeTimeZoneDraft = String(nextValue || "UTC")
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Idle timeout"
                description: "Choose how long a non-interactive connection can stay idle."

                Components.AppComboBox {
                    id: waitTimeoutCombo
                    width: 260
                    model: [
                        { label: "60 seconds - very strict", value: "60" },
                        { label: "300 seconds - strict", value: "300" },
                        { label: "900 seconds - default", value: "900" },
                        { label: "3600 seconds - relaxed", value: "3600" },
                        { label: "28800 seconds - legacy", value: "28800" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot ? pageRoot.databaseRuntimeWaitTimeoutDraft : "900", 2)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (pageRoot) {
                            pageRoot.databaseRuntimeWaitTimeoutDraft = String((item && item.value) || "900")
                        }
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Interactive timeout"
                description: "Choose how long an interactive session such as a terminal client can stay idle."

                Components.AppComboBox {
                    id: interactiveTimeoutCombo
                    width: 260
                    model: [
                        { label: "300 seconds - strict", value: "300" },
                        { label: "900 seconds - default", value: "900" },
                        { label: "3600 seconds - relaxed", value: "3600" },
                        { label: "28800 seconds - legacy", value: "28800" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot ? pageRoot.databaseRuntimeInteractiveTimeoutDraft : "900", 1)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (pageRoot) {
                            pageRoot.databaseRuntimeInteractiveTimeoutDraft = String((item && item.value) || "900")
                        }
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Log queries without indexes"
                description: "Write a log entry for queries that are likely missing indexes."

                Components.AppComboBox {
                    id: logQueriesCombo
                    width: 220
                    model: [
                        { label: "Off - quieter", value: false },
                        { label: "On - noisier", value: true }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot ? pageRoot.databaseRuntimeLogQueriesNotUsingIndexesDraft : false, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (pageRoot) {
                            pageRoot.databaseRuntimeLogQueriesNotUsingIndexesDraft = Boolean(item && item.value)
                        }
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Log slow admin statements"
                description: "Include administrative statements in the slow query log."

                Components.AppComboBox {
                    id: logSlowAdminCombo
                    width: 220
                    model: [
                        { label: "Off - default", value: false },
                        { label: "On - include admin statements", value: true }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot ? pageRoot.databaseRuntimeLogSlowAdminStatementsDraft : false, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (pageRoot) {
                            pageRoot.databaseRuntimeLogSlowAdminStatementsDraft = Boolean(item && item.value)
                        }
                    }
                }
            }

            Components.SettingsLabeledControl {
                visible: String((dashboardBridge && dashboardBridge.activeDatabaseRuntimeBrand) || "").toLowerCase() !== "mariadb"
                title: "Extra slow log details"
                description: "Include extra fields in MySQL slow query log lines."

                Components.AppComboBox {
                    id: logSlowExtraCombo
                    width: 220
                    model: [
                        { label: "Off - smaller logs", value: false },
                        { label: "On - more detail", value: true }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot ? pageRoot.databaseRuntimeLogSlowExtraDraft : false, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (pageRoot) {
                            pageRoot.databaseRuntimeLogSlowExtraDraft = Boolean(item && item.value)
                        }
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Throttle indexless queries"
                description: "Limit how many indexless queries are written to the slow query log per minute."

                Components.AppComboBox {
                    id: logThrottleCombo
                    width: 260
                    model: [
                        { label: "0 - no limit", value: "0" },
                        { label: "10 per minute - light throttle", value: "10" },
                        { label: "30 per minute - balanced", value: "30" },
                        { label: "60 per minute - moderate", value: "60" },
                        { label: "120 per minute - heavy", value: "120" },
                        { label: "300 per minute - very heavy", value: "300" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot ? pageRoot.databaseRuntimeLogThrottleQueriesNotUsingIndexesDraft : "0", 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (pageRoot) {
                            pageRoot.databaseRuntimeLogThrottleQueriesNotUsingIndexesDraft = String((item && item.value) || "0")
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("restore.default")
                onClicked: resetSettings()
            }

            Components.AppButton {
                id: saveButton
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                successText: "Saved"
                successDurationMs: 5000
                onClicked: {
                    var payload = {
                        bind_address: pageRoot.databaseRuntimeBindAddressDraft,
                        time_zone: pageRoot.databaseRuntimeTimeZoneDraft,
                        wait_timeout: pageRoot.databaseRuntimeWaitTimeoutDraft,
                        interactive_timeout: pageRoot.databaseRuntimeInteractiveTimeoutDraft,
                        log_queries_not_using_indexes: pageRoot.databaseRuntimeLogQueriesNotUsingIndexesDraft,
                        log_slow_admin_statements: pageRoot.databaseRuntimeLogSlowAdminStatementsDraft,
                        log_slow_extra: pageRoot.databaseRuntimeLogSlowExtraDraft,
                        log_throttle_queries_not_using_indexes: pageRoot.databaseRuntimeLogThrottleQueriesNotUsingIndexesDraft
                    }
                    var ok = dashboardBridge.saveDatabaseRuntimeSettings(payload)
                    feedbackText = dashboardBridge.databaseRuntimeMessage
                    feedbackError = !ok
                    if (ok) {
                        saveButton.showSuccess()
                        pageRoot.refreshDatabaseRuntimeSettingsDraft()
                    } else {
                        saveButton.successActive = false
                    }
                    if (ok && pageRoot && pageRoot.databaseRunning) {
                        var appWindow = mainWindow()
                        if (appWindow && appWindow.openGlobalConfirm) {
                            appWindow.openGlobalConfirm(
                                Strings.t("restart.database.runtime"),
                                "Database runtime is running. Restart now to apply the new settings?",
                                "database.restart_after_runtime_save",
                                {},
                                Strings.t("restart"),
                                Strings.t("later"),
                                runtimeWindow
                            )
                        }
                    }
                }
            }
        }
    }
}


