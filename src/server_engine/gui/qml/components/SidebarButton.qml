import QtQuick
import QtQuick.Effects
import "../theme"
import Qt5Compat.GraphicalEffects

Rectangle {
    id: sidebarButton

    required property var dashboardBridge
    required property string itemId
    required property string label
    required property string iconName

    property bool active: dashboardBridge.currentPage === itemId

    radius: 6
    color: active ? Theme.accentStrong : "transparent"

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        height: 24

        Item {
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: navIconSource
                anchors.fill: parent
                visible: false
                source: "../icons/lucide/" + sidebarButton.iconName + ".svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            ColorOverlay {
                anchors.fill: navIconSource
                source: navIconSource
                color: sidebarButton.active ? Theme.sidebarButtonActiveText : Theme.muted
            }
        }

        Text {
            text: sidebarButton.label
            width: sidebarButton.width - 54
            anchors.verticalCenter: parent.verticalCenter
            color: sidebarButton.active ? Theme.sidebarButtonActiveText : Theme.text
            font.pixelSize: 14
            font.weight: sidebarButton.active ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: sidebarButton.dashboardBridge.setCurrentPage(sidebarButton.itemId)
    }
}
