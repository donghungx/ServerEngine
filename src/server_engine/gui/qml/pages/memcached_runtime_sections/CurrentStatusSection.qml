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
                text: Strings.t("review.runtime.state.active.port.and.selected.runtime.version")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 168
                radius: Theme.radius
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    Text { text: Strings.t("service.state"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.activeMemcachedServiceState; color: Theme.text; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Text { text: Strings.t("port"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.activeMemcachedPort; color: Theme.text; font.pixelSize: 14 }
                    Text { text: Strings.t("runtime"); color: Theme.muted; font.pixelSize: 11 }
                    Text { text: dashboardBridge.activeMemcachedRuntimeLabel; color: Theme.text; font.pixelSize: 14 }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
