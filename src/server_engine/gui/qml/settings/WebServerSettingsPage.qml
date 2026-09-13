import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components" as Components
import "../theme"
import "../i18n"

Item {
    required property var bridge
    required property var window
    required property var appSettingsWindow
    property alias webServerCombo: webServerCombo
    Layout.fillWidth: true
    Layout.fillHeight: true

    function stopGuideText() {
        var label = String(bridge.currentWebServerLabel || "")
        if (label.length === 0) {
            return ""
        }
        return Strings.t("web.server.settings.stop.current").replace("%1", label)
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            Components.SettingsLabeledControl {
                title: Strings.t("web.server") + ":"

                Components.AppComboBox {
                    id: webServerCombo
                    model: ["apache", "nginx"]
                }

                descriptionElement: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: Strings.t("web.server.settings.description")
                        color: Theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Strings.t("web.server.settings.switch.note")
                        color: Theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: stopGuideText()
                        color: Theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                    }
                }
            }

            Components.SettingsLabeledControl {
                title: "Keep-alive timeout"
                description: "How long the server should keep a client connection open while waiting for the next request."

                Components.AppComboBox {
                    id: webServerKeepAliveTimeoutCombo
                    width: 160
                    model: [
                        "5s",
                        "10s",
                        "15s",
                        "30s",
                        "45s",
                        "60s",
                        "75s",
                        "120s"
                    ]
                    currentIndex: appSettingsWindow.safeComboIndex(
                        webServerKeepAliveTimeoutCombo,
                        appSettingsWindow.webServerKeepAliveTimeoutDraft
                    )
                    onCurrentIndexChanged: {
                        appSettingsWindow.webServerKeepAliveTimeoutDraft = currentText
                    }
                }
            }

            Components.SettingsCheckableOption {
                id: webServerRestartAfterChangesCheck
                title: "Restart after changes"
                description: "Restart the active web server automatically after you save changes."
                checked: appSettingsWindow.webServerRestartAfterChangesDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.webServerRestartAfterChangesDraft = nextChecked
                }
            }

            Components.SettingsCheckableOption {
                id: webServerEnableCompressionCheck
                title: "Enable compression"
                description: "Compress text responses before they are sent to the browser."
                checked: appSettingsWindow.webServerEnableCompressionDraft
                onToggled: function(nextChecked) {
                    appSettingsWindow.webServerEnableCompressionDraft = nextChecked
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: appSettingsWindow.scopedAppSettingsMessage
            color: bridge.appSettingsError ? Theme.danger : Theme.success
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
                onClicked: bridge.saveDefaultWebServerSelection(webServerCombo.currentText)
            }
        }
    }
}
