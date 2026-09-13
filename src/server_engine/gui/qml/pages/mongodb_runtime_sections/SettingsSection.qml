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

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (pageRoot && pageRoot.dashboardBridge) {
            return pageRoot.dashboardBridge
        }
        return ({})
    }

    function loadSettings() {
        if (pageRoot && pageRoot.refreshMongodbGeneralDraft) {
            pageRoot.refreshMongodbGeneralDraft()
        }
    }

    function resetSettings() {
        if (!pageRoot) {
            return
        }
        pageRoot.mongodbGeneralBindIpDraft = "127.0.0.1"
        pageRoot.mongodbGeneralBindIpAllDraft = false
        pageRoot.mongodbGeneralTlsModeDraft = "disabled"
        pageRoot.mongodbGeneralSystemLogAppendDraft = true
        pageRoot.mongodbGeneralSystemLogVerbosityDraft = "0"
        pageRoot.mongodbGeneralJavascriptEnabledDraft = true
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
            if (actionId === "mongodb.restart_after_general_save") {
                if (bridge().restartMongodbRuntime) {
                    bridge().restartMongodbRuntime()
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
                description: "Choose whether MongoDB only accepts local connections or listens on all interfaces."
                selectedValue: pageRoot.mongodbGeneralBindIpAllDraft ? "0.0.0.0" : "127.0.0.1"
                model: [
                    { label: "Local only", value: "127.0.0.1" },
                    { label: "All interfaces", value: "0.0.0.0" }
                ]
                onSelected: function(nextValue) {
                    var normalized = String(nextValue || "127.0.0.1")
                    pageRoot.mongodbGeneralBindIpDraft = normalized
                    pageRoot.mongodbGeneralBindIpAllDraft = normalized !== "127.0.0.1"
                }
            }

            Components.SettingsLabeledControl {
                title: "TLS mode"
                description: "Choose how MongoDB handles TLS on the server socket."

                Components.AppComboBox {
                    width: 260
                    model: [
                        { label: "disabled - plain connections", value: "disabled" },
                        { label: "allowTLS - accept plain or TLS", value: "allowTLS" },
                        { label: "preferTLS - prefer TLS when possible", value: "preferTLS" },
                        { label: "requireTLS - TLS only", value: "requireTLS" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.mongodbGeneralTlsModeDraft, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.mongodbGeneralTlsModeDraft = String((item && item.value) || "disabled")
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: "Append to log"
                description: "Keep old log contents and append new entries on restart."
                checked: pageRoot.mongodbGeneralSystemLogAppendDraft
                onToggled: function(nextChecked) {
                    pageRoot.mongodbGeneralSystemLogAppendDraft = nextChecked
                }
            }

            Components.SettingsLabeledControl {
                title: "Log level"
                description: "Choose how much detail MongoDB writes to the log."

                Components.AppComboBox {
                    width: 360
                    model: [
                        { label: "Normal", value: "0" },
                        { label: "A bit more detail", value: "1" },
                        { label: "More detail", value: "2" },
                        { label: "Very detailed", value: "3" },
                        { label: "Extremely detailed", value: "4" },
                        { label: "Maximum detail", value: "5" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.mongodbGeneralSystemLogVerbosityDraft, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.mongodbGeneralSystemLogVerbosityDraft = String((item && item.value) || "0")
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: "Enable JavaScript"
                description: "Allow server-side JavaScript execution."
                checked: pageRoot.mongodbGeneralJavascriptEnabledDraft
                onToggled: function(nextChecked) {
                    pageRoot.mongodbGeneralJavascriptEnabledDraft = nextChecked
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
                        bind_address: pageRoot.mongodbGeneralBindIpDraft,
                        tls_mode: pageRoot.mongodbGeneralTlsModeDraft,
                        system_log_append: pageRoot.mongodbGeneralSystemLogAppendDraft,
                        system_log_verbosity: pageRoot.mongodbGeneralSystemLogVerbosityDraft,
                        javascript_enabled: pageRoot.mongodbGeneralJavascriptEnabledDraft
                    }
                    var ok = bridge().saveMongodbRuntimeSettings && bridge().saveMongodbRuntimeSettings(payload)
                    feedbackText = String(bridge().mongodbRuntimeMessage || "")
                    feedbackError = !ok
                    if (ok) {
                        saveButton.showSuccess()
                        pageRoot.refreshMongodbGeneralDraft()
                        if (pageRoot && pageRoot.mongodbRunning) {
                            var appWindow = mainWindow()
                            if (appWindow && appWindow.openGlobalConfirm) {
                                appWindow.openGlobalConfirm(
                                    Strings.t("restart.mongodb.runtime"),
                                    "MongoDB runtime is running. Restart now to apply the new settings?",
                                    "mongodb.restart_after_general_save",
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


