import QtQuick
import QtQuick.Layouts
import "../components" as Components
import "../theme"

Components.ShellCard {
    id: root
    Layout.preferredWidth: 192
    Layout.fillHeight: true
    color: Theme.surface

    required property var dashboardBridge

    border.width: 0
    radius: 0

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right

        width: 1
        color: Theme.border
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: 48
        spacing: 14

        Column {
            width: parent.width
            spacing: 6

            Repeater {
                model: root.dashboardBridge.navigationItems

                delegate: Item {
                    required property int index
                    width: parent.width
                    height: 32
                    property var navItem: root.dashboardBridge.navigationItems[index]

                    Components.SidebarButton {
                        anchors.fill: parent
                        dashboardBridge: root.dashboardBridge
                        itemId: parent.navItem.id
                        label: parent.navItem.label
                        iconName: parent.navItem.icon
                    }
                }
            }
        }
    }
}
