import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var pageRoot: ({})
    property var dashboardBridge: ({})
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

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    function loadSettings() {
        if (pageRoot && pageRoot.refreshPostgresqlGeneralDraft) {
            pageRoot.refreshPostgresqlGeneralDraft()
        }
    }

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (pageRoot && pageRoot.dashboardBridge) {
            return pageRoot.dashboardBridge
        }
        return ({})
    }

    function resetSettings() {
        if (!pageRoot) {
            return
        }
        pageRoot.postgresqlGeneralListenAddressesDraft = "127.0.0.1"
        pageRoot.postgresqlGeneralTimezoneDraft = "UTC"
        pageRoot.postgresqlGeneralLoggingCollectorDraft = false
        pageRoot.postgresqlGeneralLogDestinationDraft = "stderr"
        pageRoot.postgresqlGeneralLogMinMessagesDraft = "warning"
        pageRoot.postgresqlGeneralLogConnectionsDraft = false
        pageRoot.postgresqlGeneralLogDisconnectionsDraft = false
        pageRoot.postgresqlGeneralLogLinePrefixDraft = "%m [%p] %q%u@%d "
        pageRoot.postgresqlGeneralIdleInTransactionSessionTimeoutDraft = "0"
        feedbackText = ""
        feedbackError = false
        if (saveButton) {
            saveButton.successActive = false
        }
    }

    Component.onCompleted: loadSettings()
    onPageRootChanged: loadSettings()
    onDashboardBridgeChanged: loadSettings()

    Connections {
        target: mainWindow()

        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "postgresql.restart_after_general_save") {
                if (bridge().restartPostgresqlRuntime) {
                    bridge().restartPostgresqlRuntime()
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
                title: "Allow access"
                description: "Choose whether PostgreSQL only accepts local connections or listens on all interfaces."
                selectedValue: pageRoot.postgresqlGeneralListenAddressesDraft === "*" ? "*" : "127.0.0.1"
                model: [
                    { label: "Local only", value: "127.0.0.1" },
                    { label: "All interfaces", value: "*" }
                ]
                onSelected: function(nextValue) {
                    pageRoot.postgresqlGeneralListenAddressesDraft = String(nextValue || "127.0.0.1")
                }
            }

            Components.TimezoneSetting {
                dashboardBridge: dashboardBridge
                title: "Default time zone"
                description: "Choose the server time zone used for timestamps and conversions."
                selectedValue: pageRoot.postgresqlGeneralTimezoneDraft
                onSelectedValuePicked: function(nextValue) {
                    pageRoot.postgresqlGeneralTimezoneDraft = String(nextValue || "UTC")
                }
            }

            Components.SettingsCheckableOption {
                title: "Enable logging collector"
                description: "Collect PostgreSQL server output into a log file."
                checked: pageRoot.postgresqlGeneralLoggingCollectorDraft
                onToggled: function(nextChecked) {
                    pageRoot.postgresqlGeneralLoggingCollectorDraft = nextChecked
                }
            }

            Components.SettingsLabeledControl {
                title: "Minimum log messages"
                description: "Choose how noisy PostgreSQL should be in the logs."

                Components.AppComboBox {
                    width: 320
                    model: [
                        { label: "Debug 5", value: "debug5" },
                        { label: "Debug 4", value: "debug4" },
                        { label: "Debug 3", value: "debug3" },
                        { label: "Debug 2", value: "debug2" },
                        { label: "Debug 1", value: "debug1" },
                        { label: "Informational", value: "info" },
                        { label: "Default", value: "notice" },
                        { label: "Warnings and above", value: "warning" },
                        { label: "Errors and above", value: "error" },
                        { label: "Log only", value: "log" },
                        { label: "Fatal only", value: "fatal" },
                        { label: "Panic only", value: "panic" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.postgresqlGeneralLogMinMessagesDraft, 7)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.postgresqlGeneralLogMinMessagesDraft = String((item && item.value) || "warning")
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: "Log connections"
                description: "Write a log line when clients connect."
                checked: pageRoot.postgresqlGeneralLogConnectionsDraft
                onToggled: function(nextChecked) {
                    pageRoot.postgresqlGeneralLogConnectionsDraft = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                title: "Log disconnections"
                description: "Write a log line when clients disconnect."
                checked: pageRoot.postgresqlGeneralLogDisconnectionsDraft
                onToggled: function(nextChecked) {
                    pageRoot.postgresqlGeneralLogDisconnectionsDraft = nextChecked
                }
            }

            Components.SettingsLabeledControl {
                title: "Log line prefix"
                description: "Choose a common prefix template or type a custom format string."

                Components.AppComboBox {
                    width: 420
                    editable: true
                    editText: pageRoot.postgresqlGeneralLogLinePrefixDraft
                    model: [
                        { label: "%m [%p] %q%u@%d - timestamp, pid, user, database", value: "%m [%p] %q%u@%d " },
                        { label: "%t [%p] - timestamp and pid", value: "%t [%p] " },
                        { label: "%m [%p] [%l] - timestamp, pid, line", value: "%m [%p] [%l] " }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.postgresqlGeneralLogLinePrefixDraft, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.postgresqlGeneralLogLinePrefixDraft = String((item && item.value) || "%m [%p] %q%u@%d ")
                    }
                    onEditTextChanged: pageRoot.postgresqlGeneralLogLinePrefixDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Idle transaction timeout"
                description: "Choose how long an idle transaction can stay open."

                Components.AppComboBox {
                    width: 260
                    editable: true
                    editText: pageRoot.postgresqlGeneralIdleInTransactionSessionTimeoutDraft
                    model: [
                        { label: "Disabled", value: "0" },
                        { label: "1 minute", value: "1min" },
                        { label: "5 minutes", value: "5min" },
                        { label: "15 minutes", value: "15min" },
                        { label: "1 hour", value: "1h" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.postgresqlGeneralIdleInTransactionSessionTimeoutDraft, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.postgresqlGeneralIdleInTransactionSessionTimeoutDraft = String((item && item.value) || "0")
                    }
                    onEditTextChanged: pageRoot.postgresqlGeneralIdleInTransactionSessionTimeoutDraft = editText
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                        listen_addresses: pageRoot.postgresqlGeneralListenAddressesDraft,
                        timezone: pageRoot.postgresqlGeneralTimezoneDraft,
                        logging_collector: pageRoot.postgresqlGeneralLoggingCollectorDraft,
                        log_min_messages: pageRoot.postgresqlGeneralLogMinMessagesDraft,
                        log_connections: pageRoot.postgresqlGeneralLogConnectionsDraft,
                        log_disconnections: pageRoot.postgresqlGeneralLogDisconnectionsDraft,
                        log_line_prefix: pageRoot.postgresqlGeneralLogLinePrefixDraft,
                        idle_in_transaction_session_timeout: pageRoot.postgresqlGeneralIdleInTransactionSessionTimeoutDraft
                    }
                    var ok = bridge().savePostgresqlRuntimeSettings ? bridge().savePostgresqlRuntimeSettings(payload) : false
                    feedbackText = String(bridge().postgresqlRuntimeMessage || "")
                    feedbackError = !ok
                    if (ok) {
                        saveButton.showSuccess()
                        pageRoot.refreshPostgresqlGeneralDraft()
                        if (pageRoot && pageRoot.postgresqlRunning) {
                            var appWindow = mainWindow()
                            if (appWindow && appWindow.openGlobalConfirm) {
                                appWindow.openGlobalConfirm(
                                    "Restart PostgreSQL runtime",
                                    "PostgreSQL runtime is running. Restart now to apply the new settings?",
                                    "postgresql.restart_after_general_save",
                                    {},
                                    Strings.t("restart"),
                                    Strings.t("later"),
                                    runtimeWindow
                                )
                            }
                        }
                    } else {
                        saveButton.successActive = false
                    }
                }
            }
        }
    }
}


