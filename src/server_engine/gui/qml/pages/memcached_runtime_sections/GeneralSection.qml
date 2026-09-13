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

    function restoreDefaultsNow() {
        pageRoot.resetMemcachedGeneralDraft()
        if (saveButton) {
            saveButton.successActive = false
        }
    }

    function saveGeneralNow() {
        var ok = dashboardBridge.saveMemcachedConfigSettings({
            host: pageRoot.memcachedGeneralBindAddressDraft,
            port: pageRoot.memcachedPortDraft,
            memory_limit: pageRoot.memcachedGeneralMemoryLimitDraft,
            threads: pageRoot.memcachedGeneralThreadsDraft,
            max_connections: pageRoot.memcachedGeneralMaxConnectionsDraft,
            protocol: pageRoot.memcachedGeneralProtocolDraft,
            verbose_level: pageRoot.memcachedGeneralVerboseLevelDraft,
            disable_evictions: pageRoot.memcachedGeneralDisableEvictionsDraft
        })
        if (ok) {
            saveButton.showSuccess()
            pageRoot.refreshMemcachedConfigDraft()
        } else {
            saveButton.successActive = false
        }
        return ok
    }

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    Connections {
        target: mainWindow()
        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "memcached.restore_defaults") {
                restoreDefaultsNow()
            } else if (actionId === "memcached.restart_after_general_save") {
                if (dashboardBridge && dashboardBridge.restartMemcachedRuntime) {
                    dashboardBridge.restartMemcachedRuntime()
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
            spacing: 10

            Components.SettingsRadioGroup {
                title: "Allow access to Memcached"
                description: "Choose whether Memcached only accepts local connections or listens on all interfaces."
                selectedValue: pageRoot.memcachedGeneralBindAddressDraft
                model: [
                    { label: "Local only", value: "127.0.0.1" },
                    { label: "All interfaces", value: "0.0.0.0" }
                ]
                onSelected: function(nextValue) {
                    pageRoot.memcachedGeneralBindAddressDraft = String(nextValue || "127.0.0.1")
                }
            }

            Components.SettingsLabeledControl {
                title: "Memory limit"
                description: "Maximum item memory in megabytes."

                Components.AppComboBox {
                    width: 220
                    editable: true
                    editText: pageRoot.memcachedGeneralMemoryLimitDraft
                    model: [
                        { label: "64 MB - tiny", value: "64" },
                        { label: "128 MB - small", value: "128" },
                        { label: "256 MB - balanced", value: "256" },
                        { label: "512 MB - common", value: "512" },
                        { label: "1 GB - large", value: "1024" },
                        { label: "2 GB - very large", value: "2048" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.memcachedGeneralMemoryLimitDraft, 3)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (item && item.value !== undefined) {
                            pageRoot.memcachedGeneralMemoryLimitDraft = String(item.value)
                        }
                    }
                    onEditTextChanged: pageRoot.memcachedGeneralMemoryLimitDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Threads"
                description: "Number of worker threads used by Memcached."

                Components.AppComboBox {
                    width: 220
                    editable: true
                    editText: pageRoot.memcachedGeneralThreadsDraft
                    model: [
                        { label: "1 - single thread", value: "1" },
                        { label: "2 - small", value: "2" },
                        { label: "4 - balanced", value: "4" },
                        { label: "8 - higher concurrency", value: "8" },
                        { label: "16 - heavy load", value: "16" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.memcachedGeneralThreadsDraft, 2)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (item && item.value !== undefined) {
                            pageRoot.memcachedGeneralThreadsDraft = String(item.value)
                        }
                    }
                    onEditTextChanged: pageRoot.memcachedGeneralThreadsDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Max connections"
                description: "Maximum number of simultaneous client connections."

                Components.AppComboBox {
                    width: 240
                    editable: true
                    editText: pageRoot.memcachedGeneralMaxConnectionsDraft
                    model: [
                        { label: "256 - small", value: "256" },
                        { label: "512 - modest", value: "512" },
                        { label: "1024 - default", value: "1024" },
                        { label: "2048 - busy", value: "2048" },
                        { label: "4096 - heavy", value: "4096" },
                        { label: "8192 - very heavy", value: "8192" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.memcachedGeneralMaxConnectionsDraft, 2)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (item && item.value !== undefined) {
                            pageRoot.memcachedGeneralMaxConnectionsDraft = String(item.value)
                        }
                    }
                    onEditTextChanged: pageRoot.memcachedGeneralMaxConnectionsDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Protocol"
                description: "Choose the Memcached protocol mode."

                Components.AppComboBox {
                    width: 240
                    model: [
                        { label: "Auto - choose the best protocol", value: "auto" },
                        { label: "ASCII - classic text protocol", value: "ascii" },
                        { label: "Binary - compact binary protocol", value: "binary" }
                    ]
                    textRole: "label"
                    currentIndex: pageRoot.memcachedGeneralProtocolDraft === "ascii"
                        ? 1
                        : (pageRoot.memcachedGeneralProtocolDraft === "binary" ? 2 : 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.memcachedGeneralProtocolDraft = String((item && item.value) || "auto")
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Verbose level"
                description: "Control how much Memcached writes to the console/logs."

                Components.AppComboBox {
                    width: 320
                    model: [
                        { label: "Quiet - normal operation", value: "" },
                        { label: "Verbose (-v) - warnings and errors", value: "v" },
                        { label: "Very verbose (-vv) - includes client commands", value: "vv" },
                        { label: "Extremely verbose (-vvv) - includes internal state transitions", value: "vvv" }
                    ]
                    textRole: "label"
                    currentIndex: pageRoot.memcachedGeneralVerboseLevelDraft === "vvv"
                        ? 3
                        : (pageRoot.memcachedGeneralVerboseLevelDraft === "vv"
                            ? 2
                            : (pageRoot.memcachedGeneralVerboseLevelDraft === "v" ? 1 : 0))
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.memcachedGeneralVerboseLevelDraft = String((item && item.value) || "")
                    }
                }
            }

            Components.SettingsCheckableOption {
                title: "Disable evictions"
                description: "Return an error when memory is exhausted instead of evicting items."
                checked: pageRoot.memcachedGeneralDisableEvictionsDraft
                onToggled: function(nextChecked) {
                    pageRoot.memcachedGeneralDisableEvictionsDraft = nextChecked
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
                onClicked: {
                    var appWindow = mainWindow()
                    if (appWindow && appWindow.openGlobalConfirm) {
                        appWindow.openGlobalConfirm(
                            Strings.t("restore.default"),
                            "This will restore all Memcached general values to their defaults.",
                            "memcached.restore_defaults",
                            {},
                            Strings.t("confirm"),
                            Strings.t("cancel"),
                            runtimeWindow
                        )
                        return
                    }
                    restoreDefaultsNow()
                }
            }

            Components.AppButton {
                id: saveButton
                highlighted: true
                text: Strings.t("settings.appearance.save")
                successText: "Saved"
                successDurationMs: 5000
                onClicked: {
                    var ok = saveGeneralNow()
                    if (!ok) {
                        return
                    }
                    if (pageRoot && pageRoot.cacheRunning) {
                        var appWindow = mainWindow()
                        if (appWindow && appWindow.openGlobalConfirm) {
                            appWindow.openGlobalConfirm(
                                "Restart Required",
                                "Memcached needs to restart to apply the new settings. Do you want to restart now?",
                                "memcached.restart_after_general_save",
                                {},
                                "Restart",
                                "Cancel",
                                runtimeWindow
                            )
                            return
                        }
                    }
                }
            }
        }
    }
}



