import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    property alias nginxWorkerProcessesField: nginxWorkerProcessesField
    property alias nginxWorkerConnectionsField: nginxWorkerConnectionsField
    property alias nginxKeepaliveTimeoutField: nginxKeepaliveTimeoutField
    property alias nginxClientMaxBodySizeField: nginxClientMaxBodySizeField
    property alias nginxErrorLogPathField: nginxErrorLogPathField
    property alias nginxGlobalDirectivesField: nginxGlobalDirectivesField
    property alias nginxSendfileCheck: nginxSendfileCheck
    property alias nginxGzipCheck: nginxGzipCheck
    property alias nginxServerTokensCheck: nginxServerTokensCheck
    Layout.fillWidth: true
    Layout.fillHeight: true

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

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("settings")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: "Configure the active Nginx runtime settings used by the web server."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Components.SettingsLabeledControl {
                title: "Global directives"
                description: "Add raw Nginx global directives that are passed with -g when the runtime starts."

                Components.AppScrollEditor {
                    id: nginxGlobalDirectivesField
                    Layout.fillWidth: true
                    height: 96
                    text: pageRoot.nginxGlobalDirectivesDraft
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    textFormat: TextEdit.PlainText
                    fontFamily: "Menlo"
                    fontPixelSize: 12
                    showContextMenu: true
                    placeholderText: "worker_rlimit_nofile 2048;\\nmap $http_user_agent $is_bot { default 0; ~bot 1; }"
                    onTextChanged: pageRoot.nginxGlobalDirectivesDraft = text
                }
            }

            Components.SettingsLabeledControl {
                title: "Worker processes"
                description: "Set how many worker processes Nginx should launch. Use `auto` to match CPU cores."

                Components.AppComboBox {
                    id: nginxWorkerProcessesField
                    width: 220
                    editable: true
                    editText: pageRoot.nginxWorkerProcessesDraft
                    model: [
                        { label: "1 - single worker", value: "1" },
                        { label: "2 - light load", value: "2" },
                        { label: "4 - balanced", value: "4" },
                        { label: "8 - higher concurrency", value: "8" },
                        { label: "auto - match CPU cores", value: "auto" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.nginxWorkerProcessesDraft, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (item && item.value !== undefined) {
                            pageRoot.nginxWorkerProcessesDraft = String(item.value)
                        }
                    }
                    onEditTextChanged: pageRoot.nginxWorkerProcessesDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Worker connections"
                description: "Maximum simultaneous connections handled by each worker process."

                Components.AppComboBox {
                    id: nginxWorkerConnectionsField
                    width: 240
                    editable: true
                    editText: pageRoot.nginxWorkerConnectionsDraft
                    model: [
                        { label: "256 - small", value: "256" },
                        { label: "512 - modest", value: "512" },
                        { label: "1024 - default", value: "1024" },
                        { label: "2048 - busy", value: "2048" },
                        { label: "4096 - high", value: "4096" },
                        { label: "8192 - very high", value: "8192" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.nginxWorkerConnectionsDraft, 2)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (item && item.value !== undefined) {
                            pageRoot.nginxWorkerConnectionsDraft = String(item.value)
                        }
                    }
                    onEditTextChanged: pageRoot.nginxWorkerConnectionsDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Keepalive timeout"
                description: "How long Nginx keeps idle client connections open before closing them."

                Components.AppComboBox {
                    id: nginxKeepaliveTimeoutField
                    width: 220
                    editable: true
                    editText: pageRoot.nginxKeepaliveTimeoutDraft
                    model: [
                        { label: "5s - very short", value: "5s" },
                        { label: "10s - short", value: "10s" },
                        { label: "30s - responsive", value: "30s" },
                        { label: "45s - balanced", value: "45s" },
                        { label: "60s - common", value: "60s" },
                        { label: "65s - default", value: "65" },
                        { label: "75s - longer", value: "75s" },
                        { label: "120s - relaxed", value: "120s" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.nginxKeepaliveTimeoutDraft, 5)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (item && item.value !== undefined) {
                            pageRoot.nginxKeepaliveTimeoutDraft = String(item.value)
                        }
                    }
                    onEditTextChanged: pageRoot.nginxKeepaliveTimeoutDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Client max body size"
                description: "Maximum request body size accepted by Nginx for uploads and form posts."

                Components.AppComboBox {
                    id: nginxClientMaxBodySizeField
                    width: 240
                    editable: true
                    editText: pageRoot.nginxClientMaxBodySizeDraft
                    model: [
                        { label: "1m - tiny", value: "1m" },
                        { label: "4m - small", value: "4m" },
                        { label: "8m - modest", value: "8m" },
                        { label: "16m - medium", value: "16m" },
                        { label: "32m - large", value: "32m" },
                        { label: "64m - default", value: "64m" },
                        { label: "128m - very large", value: "128m" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.nginxClientMaxBodySizeDraft, 5)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        if (item && item.value !== undefined) {
                            pageRoot.nginxClientMaxBodySizeDraft = String(item.value)
                        }
                    }
                    onEditTextChanged: pageRoot.nginxClientMaxBodySizeDraft = editText
                }
            }

            Components.SettingsLabeledControl {
                title: "Error log path"
                description: "Where Nginx writes startup and runtime error logs."

                Components.AppComboBox {
                    id: nginxErrorLogPathField
                    width: 420
                    editable: true
                    editText: pageRoot.nginxErrorLogPathDraft
                    model: [
                        { label: "Default runtime log path", value: "" },
                        { label: "~/Library/Application Support/Server Engine/logs/nginx/nginx-error.log", value: "~/Library/Application Support/Server Engine/logs/nginx/nginx-error.log" },
                        { label: "~/Library/Application Support/Server Engine/logs/nginx/custom-error.log", value: "~/Library/Application Support/Server Engine/logs/nginx/custom-error.log" },
                        { label: "~/Library/Application Support/Server Engine/logs/nginx/startup.log", value: "~/Library/Application Support/Server Engine/logs/nginx/startup.log" }
                    ]
                    textRole: "label"
                    currentIndex: indexForValue(model, pageRoot.nginxErrorLogPathDraft, 0)
                    onCurrentIndexChanged: {
                        var item = model[currentIndex]
                        pageRoot.nginxErrorLogPathDraft = String((item && item.value) || "")
                    }
                    onEditTextChanged: pageRoot.nginxErrorLogPathDraft = editText
                }
            }

            Components.SettingsCheckableOption {
                id: nginxSendfileCheck
                title: "Sendfile"
                description: "Use the operating system sendfile path for static file responses."
                checked: pageRoot.nginxSendfileDraft
                onToggled: pageRoot.nginxSendfileDraft = checked
            }

            Components.SettingsCheckableOption {
                id: nginxGzipCheck
                title: "Gzip"
                description: "Compress supported responses before sending them to the browser."
                checked: pageRoot.nginxGzipDraft
                onToggled: pageRoot.nginxGzipDraft = checked
            }

            Components.SettingsCheckableOption {
                id: nginxServerTokensCheck
                title: "Server tokens"
                description: "Show or hide the Nginx version in generated headers and error pages."
                checked: pageRoot.nginxServerTokensDraft
                onToggled: pageRoot.nginxServerTokensDraft = checked
            }

            Item { Layout.fillWidth: true; Layout.fillHeight: true }
        }

        footerLeft: Text {
            text: dashboardBridge.nginxRuntimeMessage
            color: dashboardBridge.nginxRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: parent.width
            verticalAlignment: Text.AlignVCenter
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                accent: true
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    var ok = dashboardBridge.saveNginxAppSettings(
                        pageRoot.nginxWorkerProcessesDraft,
                        pageRoot.nginxWorkerConnectionsDraft,
                        pageRoot.nginxKeepaliveTimeoutDraft,
                        pageRoot.nginxClientMaxBodySizeDraft,
                        pageRoot.nginxSendfileDraft,
                        pageRoot.nginxGzipDraft,
                        pageRoot.nginxServerTokensDraft,
                        pageRoot.nginxErrorLogPathDraft,
                        pageRoot.nginxGlobalDirectivesDraft
                    )
                    if (ok) {
                        pageRoot.refreshNginxConfigDraft()
                    }
                }
            }
        }
    }
}
