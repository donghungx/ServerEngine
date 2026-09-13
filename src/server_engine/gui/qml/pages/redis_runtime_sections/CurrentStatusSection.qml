import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"
        contentMargins: 0
        contentSpacing: 10
        footerRightMargin: 0
        footerBottomMargin: 0

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("current.status")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("review.runtime.state.port.password.status.and.storage.paths")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                radius: Theme.radius
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    Text { text: Strings.t("service.state"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.activeRedisServiceState; color: Theme.text; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Text { text: Strings.t("port"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.activeRedisPort; color: Theme.text; font.pixelSize: 14 }
                    Text { text: Strings.t("password"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.redisPassword.length > 0 ? "Configured" : "Not set"; color: Theme.text; font.pixelSize: 14 }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
