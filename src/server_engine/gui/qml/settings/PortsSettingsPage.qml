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
    property alias webPortField: webPortField
    property alias databasePortField: databasePortField
    property alias redisPortField: redisPortField
    property alias memcachedPortField: memcachedPortField
    property alias mailpitSmtpPortField: mailpitSmtpPortField
    property alias mailpitHttpPortField: mailpitHttpPortField
    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            Components.SettingsLabeledInput {
                title: Strings.t("web.server")
                description: "One shared port for whichever web server is active, Apache or Nginx."

                Components.AppTextField {
                    id: webPortField
                    width: 240
                    placeholderText: "80"
                }
            }

            Components.SettingsLabeledInput {
                title: Strings.t("database")
                description: "Used by the selected database runtime, MariaDB or MySQL."

                Components.AppTextField {
                    id: databasePortField
                    width: 240
                    placeholderText: "3306"
                }
            }

            Components.SettingsLabeledInput {
                title: Strings.t("redis")
                description: "Change this when port 6379 is occupied by another Redis instance."

                Components.AppTextField {
                    id: redisPortField
                    width: 240
                    placeholderText: "6379"
                }
            }

            Components.SettingsLabeledInput {
                title: Strings.t("memcached")
                description: "Memcached daemon listen port used by your local projects."

                Components.AppTextField {
                    id: memcachedPortField
                    width: 240
                    placeholderText: "11211"
                }
            }

            Components.SettingsLabeledInput {
                Layout.fillWidth: true
                title: Strings.t("mailpit.smtp")
                description: "Incoming SMTP port for app mail delivery."

                Components.AppTextField {
                    id: mailpitSmtpPortField
                    width: 240
                    placeholderText: "1025"
                }
            }

            Components.SettingsLabeledInput {
                Layout.fillWidth: true
                title: Strings.t("mailpit.web")
                description: "Web inbox UI port for viewing captured emails."

                Components.AppTextField {
                    id: mailpitHttpPortField
                    width: 240
                    placeholderText: "8025"
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
                text: Strings.t("set.default.ports")
                onClicked: window.defaultPortsConfirmOpen = true
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                accent: true
                onClicked: {
                    bridge.savePortsAppSettings(
                        webPortField.text,
                        databasePortField.text,
                        redisPortField.text,
                        memcachedPortField.text,
                        mailpitSmtpPortField.text,
                        mailpitHttpPortField.text
                    )
                }
            }
        }
    }
}
