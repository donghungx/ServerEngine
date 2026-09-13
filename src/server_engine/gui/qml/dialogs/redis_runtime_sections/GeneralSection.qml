import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    function logLevelIndex(value) {
        var normalized = String(value || "notice")
        if (normalized === "debug") {
            return 0
        }
        if (normalized === "verbose") {
            return 1
        }
        if (normalized === "warning") {
            return 3
        }
        return 2
    }

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    function saveGeneralNow() {
        var ok = dashboardBridge.saveRedisGeneralSettings({
            bind_address: pageRoot.redisGeneralBindAddressDraft,
            protected_mode: pageRoot.redisGeneralProtectedModeDraft,
            appendonly: pageRoot.redisGeneralAppendOnlyDraft,
            log_level: pageRoot.redisGeneralLogLevelDraft,
            db_filename: pageRoot.redisGeneralDbFilenameDraft
        })
        if (ok) {
            saveButton.showSuccess()
            pageRoot.refreshRedisConfigDraft()
            if (pageRoot && pageRoot.redisRunning) {
                var appWindow = mainWindow()
                if (appWindow && appWindow.openGlobalConfirm) {
                    appWindow.openGlobalConfirm(
                        "Restart Required",
                        "Redis needs to restart to apply the new settings. Do you want to restart now?",
                        "redis.restart_after_general_save",
                        {},
                        "Restart",
                        "Cancel",
                        runtimeWindow
                    )
                } else if (dashboardBridge && dashboardBridge.restartRedisRuntime) {
                    dashboardBridge.restartRedisRuntime()
                }
            }
        } else {
            saveButton.successActive = false
        }
        return ok
    }

    Connections {
        target: mainWindow()
        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "redis.restart_after_general_save") {
                if (dashboardBridge && dashboardBridge.restartRedisRuntime) {
                    dashboardBridge.restartRedisRuntime()
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
                description: "Choose whether Redis only accepts local connections or listens on all interfaces."
                selectedValue: pageRoot.redisGeneralBindAddressDraft === "0.0.0.0" ? "0.0.0.0" : "127.0.0.1"
                model: [
                    { label: "Local only", value: "127.0.0.1" },
                    { label: "All interfaces", value: "0.0.0.0" }
                ]
                onSelected: function(nextValue) {
                    pageRoot.redisGeneralBindAddressDraft = String(nextValue || "127.0.0.1")
                }
            }

            Components.SettingsCheckableOption {
                title: "Protected mode"
                description: "Keep Redis in protected mode so remote connections stay restricted."
                checked: pageRoot.redisGeneralProtectedModeDraft
                onToggled: function(nextChecked) {
                    pageRoot.redisGeneralProtectedModeDraft = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                title: "Append-only persistence"
                description: "Write changes to an append-only file in addition to snapshot persistence."
                checked: pageRoot.redisGeneralAppendOnlyDraft
                onToggled: function(nextChecked) {
                    pageRoot.redisGeneralAppendOnlyDraft = nextChecked
                }
            }

            Components.SettingsLabeledControl {
                title: "Log level"
                description: "Control how much detail Redis writes to its log output."
                descriptionElement: Text {
                    Layout.fillWidth: true
                    text: "Use a quieter mode for normal operation, or a more verbose mode when you need troubleshooting details."
                    color: Theme.muted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                Components.AppComboBox {
                    width: 240
                    model: [
                        { label: "Debug - most detailed, best for troubleshooting", value: "debug" },
                        { label: "Verbose - detailed server activity", value: "verbose" },
                        { label: "Notice - normal operational messages", value: "notice" },
                        { label: "Warning - only important warnings and errors", value: "warning" }
                    ]
                    textRole: "label"
                    currentIndex: logLevelIndex(pageRoot.redisGeneralLogLevelDraft)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.redisGeneralLogLevelDraft = String((item && item.value) || "notice")
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
                id: saveButton
                highlighted: true
                text: Strings.t("settings.appearance.save")
                successText: "Saved"
                successDurationMs: 5000
                onClicked: saveGeneralNow()
            }
        }
    }
}
