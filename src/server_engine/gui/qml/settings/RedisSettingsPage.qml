import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import "../components" as Components
import "../theme"
import "../i18n"

Item {
    required property var bridge
    required property var window
    required property var appSettingsWindow
    property alias redisAppSettingsRuntimeCombo: redisAppSettingsRuntimeCombo
    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        Column {
            width: parent.width
            spacing: 10

            Text {
                width: parent.width
                text: Strings.t("redis.settings")
                color: Theme.text
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: Strings.t("choose.the.redis.runtime.version.used.by.redis.service.operations")
                color: Theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Column {
                width: parent.width
                spacing: 6

                Text {
                    text: Strings.t("redis.runtime")
                    color: Theme.muted
                    font.pixelSize: 12
                }

                Components.AppComboBox {
                    id: redisAppSettingsRuntimeCombo
                    width: 240
                    model: appSettingsWindow.cacheRuntimeModel
                    textRole: "label"
                }
            }

        }

        footerLeft: Text {
            text: appSettingsWindow.scopedAppSettingsMessage
            color: bridge.appSettingsError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: parent.width
            verticalAlignment: Text.AlignVCenter
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                accent: true
                text: Strings.t("settings.appearance.save")
                onClicked: {
                    var redisRuntimeId = redisAppSettingsRuntimeCombo.currentIndex >= 0 && appSettingsWindow.cacheRuntimeModel.length > redisAppSettingsRuntimeCombo.currentIndex
                        ? appSettingsWindow.cacheRuntimeModel[redisAppSettingsRuntimeCombo.currentIndex].id
                        : ""
                    bridge.saveRedisAppSettings(redisRuntimeId)
                }
            }
        }
    }
}
