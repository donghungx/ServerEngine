import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    anchors.fill: parent

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    function saveGeneralNow() {
        var ok = dashboardBridge.saveMailpitGeneralSettings({
            database: "",
            persistent_storage: pageRoot.mailpitGeneralPersistentStorageDraft,
            max_messages: pageRoot.mailpitGeneralMaxMessagesDraft,
            max_age: pageRoot.mailpitGeneralMaxAgeDraft,
            compression: pageRoot.mailpitGeneralCompressionDraft,
            label: pageRoot.mailpitGeneralLabelDraft,
            tenant_id: pageRoot.mailpitGeneralTenantIdDraft,
            log_file: pageRoot.mailpitGeneralLogFileDraft,
            logging_mode: pageRoot.mailpitGeneralLoggingModeDraft,
            use_message_dates: pageRoot.mailpitGeneralUseMessageDatesDraft,
            ignore_duplicate_ids: pageRoot.mailpitGeneralIgnoreDuplicateIdsDraft
        })
        if (ok) {
            saveButton.showSuccess()
            if (pageRoot && pageRoot.mailpitRunning) {
                var appWindow = mainWindow()
                if (appWindow && appWindow.openGlobalConfirm) {
                    appWindow.openGlobalConfirm(
                        "Restart Required",
                        "Mailpit needs to restart to apply the new settings. Do you want to restart now?",
                        "mailpit.restart_after_general_save",
                        {},
                        "Restart",
                        "Cancel",
                        runtimeWindow
                    )
                } else if (dashboardBridge && dashboardBridge.restartMailpitRuntime) {
                    dashboardBridge.restartMailpitRuntime()
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
            if (actionId === "mailpit.restart_after_general_save") {
                if (dashboardBridge && dashboardBridge.restartMailpitRuntime) {
                    dashboardBridge.restartMailpitRuntime()
                }
            }
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 16

                Components.SettingsCheckableOption {
                    title: "Keep Mailpit emails"
                    description: "Store Mailpit messages in the app support data directory so they survive restart."
                    checked: pageRoot.mailpitGeneralPersistentStorageDraft
                    onToggled: function(nextChecked) {
                        pageRoot.mailpitGeneralPersistentStorageDraft = nextChecked
                    }
                }

                Components.SettingsLabeledControl {
                    title: "Max messages"
                    description: "Choose a common storage limit or type a custom number."

                    Components.AppComboBox {
                        width: 260
                        editable: true
                        editText: pageRoot.mailpitGeneralMaxMessagesDraft
                        model: [
                            { label: "100 - tiny", value: "100" },
                            { label: "250 - small", value: "250" },
                            { label: "500 - default", value: "500" },
                            { label: "1000 - medium", value: "1000" },
                            { label: "2500 - large", value: "2500" },
                            { label: "5000 - very large", value: "5000" }
                        ]
                        textRole: "label"
                        onActivated: function(activatedIndex) {
                            var item = activatedIndex >= 0 && activatedIndex < model.length ? model[activatedIndex] : null
                            pageRoot.mailpitGeneralMaxMessagesDraft = String((item && item.value) || "500")
                        }
                        onEditTextChanged: pageRoot.mailpitGeneralMaxMessagesDraft = editText
                    }
                }

                Components.SettingsLabeledControl {
                    title: "Max age"
                    description: "Choose a common retention window or type a custom duration like 36h."

                    Components.AppComboBox {
                        width: 260
                        editable: true
                        editText: pageRoot.mailpitGeneralMaxAgeDraft
                        model: [
                            { label: "1d - very short", value: "1d" },
                            { label: "3d - short", value: "3d" },
                            { label: "7d - one week", value: "7d" },
                            { label: "14d - two weeks", value: "14d" },
                            { label: "30d - one month", value: "30d" }
                        ]
                        textRole: "label"
                        onActivated: function(activatedIndex) {
                            var item = activatedIndex >= 0 && activatedIndex < model.length ? model[activatedIndex] : null
                            pageRoot.mailpitGeneralMaxAgeDraft = String((item && item.value) || "14d")
                        }
                        onEditTextChanged: pageRoot.mailpitGeneralMaxAgeDraft = editText
                    }
                }

                Components.SettingsLabeledControl {
                    title: "Compression"
                    description: "Tune how much Mailpit compresses stored raw messages."

                    Components.AppComboBox {
                        width: 320
                        model: [
                            { label: "Level 0 - no compression", value: "0" },
                            { label: "Level 1 - balanced default", value: "1" },
                            { label: "Level 2 - smaller storage, more CPU", value: "2" },
                            { label: "Level 3 - maximum compression", value: "3" }
                        ]
                        textRole: "label"
                        currentIndex: pageRoot.mailpitGeneralCompressionDraft === "3"
                            ? 3
                            : (pageRoot.mailpitGeneralCompressionDraft === "2"
                                ? 2
                                : (pageRoot.mailpitGeneralCompressionDraft === "0" ? 0 : 1))
                        onCurrentIndexChanged: {
                            var item = model[currentIndex]
                            pageRoot.mailpitGeneralCompressionDraft = String((item && item.value) || "1")
                        }
                    }
                }

                Components.SettingsCheckableOption {
                    title: "Use message dates"
                    description: "Store messages using the original email date instead of the receive time."
                    checked: pageRoot.mailpitGeneralUseMessageDatesDraft
                    onToggled: function(nextChecked) {
                        pageRoot.mailpitGeneralUseMessageDatesDraft = nextChecked
                    }
                }

                Components.SettingsCheckableOption {
                    title: "Ignore duplicate IDs"
                    description: "Keep incoming mail even when Mailpit sees the same Message-ID more than once."
                    checked: pageRoot.mailpitGeneralIgnoreDuplicateIdsDraft
                    onToggled: function(nextChecked) {
                        pageRoot.mailpitGeneralIgnoreDuplicateIdsDraft = nextChecked
                    }
                }

                Components.SettingsLabeledControl {
                    title: "Logging mode"
                    description: "Choose how chatty Mailpit should be in the logs."

                    Components.AppComboBox {
                        width: 320
                        model: [
                            { label: "Default - normal logging", value: "default" },
                            { label: "Quiet - errors only", value: "quiet" },
                            { label: "Verbose - more runtime detail", value: "verbose" }
                        ]
                        textRole: "label"
                        currentIndex: pageRoot.mailpitGeneralLoggingModeDraft === "quiet"
                            ? 1
                            : (pageRoot.mailpitGeneralLoggingModeDraft === "verbose" ? 2 : 0)
                        onCurrentIndexChanged: {
                            var item = model[currentIndex]
                            pageRoot.mailpitGeneralLoggingModeDraft = String((item && item.value) || "default")
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
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
