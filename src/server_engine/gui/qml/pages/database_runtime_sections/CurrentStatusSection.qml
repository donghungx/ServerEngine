import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    Column {
        anchors.fill: parent
        spacing: 14
        Rectangle {
            width: parent.width; height: 140; radius: Theme.radius
            color: Theme.surface; border.color: Theme.border; border.width: 1
            Column {
                anchors.fill: parent; anchors.margins: 16; spacing: 10
                Text { text: Strings.t("runtime.state"); color: Theme.muted; font.pixelSize: 12 }
                Text { text: dashboardBridge.activeDatabaseServiceState; color: Theme.text; font.pixelSize: 24; font.weight: Font.DemiBold }
                Text {
                    text: dashboardBridge.databaseRuntimeMessage.length > 0 ? dashboardBridge.databaseRuntimeMessage : "No recent runtime feedback."
                    color: dashboardBridge.databaseRuntimeError ? "#bb4d4d" : Theme.muted
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }
        }
    }
}
