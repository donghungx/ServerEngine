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
    property alias phpMyAdminVersionCombo: phpMyAdminVersionCombo
    property alias phpMyAdminPhpVersionCombo: phpMyAdminPhpVersionCombo
    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Components.SettingsLabeledControl {
                title: Strings.t("phpmyadmin.version")
                description: "Choose which phpMyAdmin release to install and manage."

                Components.AppComboBox {
                    id: phpMyAdminVersionCombo
                    width: 240
                    model: bridge.appSettingsPhpMyAdminVersions
                }
            }

            Components.SettingsLabeledControl {
                title: Strings.t("php.runtime.for.phpmyadmin")
                description: "Select the PHP runtime phpMyAdmin should use. Some phpMyAdmin versions may not work well with every PHP version."

                Components.AppComboBox {
                    id: phpMyAdminPhpVersionCombo
                    width: 240
                    model: bridge.appSettingsInstalledPhpVersions
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
                    bridge.savePhpMyAdminAppSettings(
                        phpMyAdminVersionCombo.currentText,
                        phpMyAdminPhpVersionCombo.currentText
                    )
                }
            }
        }
    }
}
