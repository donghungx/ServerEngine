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
    property alias phpDefaultVersionCombo: phpDefaultVersionCombo
    property alias phpLogToFileCheck: phpLogToFileCheck
    property alias phpLogToScreenCheck: phpLogToScreenCheck
    property alias phpLogPathField: phpLogPathField
    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            Components.SettingsLabeledInput {
                title: Strings.t("default.php.version")

                Components.AppComboBox {
                    id: phpDefaultVersionCombo
                    width: 240
                    model: bridge.appSettingsPhpVersions
                }
            }

            Components.SettingsCheckableOption {
                id: phpLogToFileCheck
                title: Strings.t("log.to.file")
                description: Strings.t("Write PHP output to a log file for later inspection.")
                checked: false
            }

            Components.SettingsCheckableOption {
                id: phpLogToScreenCheck
                title: Strings.t("log.to.screen")
                description: Strings.t("Show PHP output directly in the app so you can watch it live.")
                checked: false
            }

            Components.SettingsLabeledInput {
                title: Strings.t("php.log.path")
                description: Strings.t("Specify the file path used when PHP logs are written to disk.")
                enabled: phpLogToFileCheck.checked
                opacity: enabled ? 1.0 : 0.55

                Components.AppTextField {
                    id: phpLogPathField
                    width: parent.width
                    placeholderText: "~/Library/Application Support/Server Engine/logs/php.log"
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
                onClicked: {
                    var phpVersion = phpDefaultVersionCombo.currentText
                    bridge.savePhpAppSettings(
                        phpVersion,
                        phpLogToFileCheck.checked,
                        phpLogToScreenCheck.checked,
                        phpLogPathField.text
                    )
                }
            }
        }
    }
}
