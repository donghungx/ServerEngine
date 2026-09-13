import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Qt.labs.platform as Native
import "../theme"
import "." as Components

Item {
    id: root

    property var profiles: []
    property string tooltip: "New terminal"
    property string iconSource: "../icons/lucide/plus.svg"

    signal profileSelected(string profileId)

    width: 24
    height: 24

    Rectangle {
        anchors.fill: parent
        color: "transparent"

        Image {
            id: iconImage
            anchors.centerIn: parent
            width: 16
            height: 16
            sourceSize.width: 16
            sourceSize.height: 16
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: root.iconSource
            visible: false
        }

        MultiEffect {
            anchors.fill: iconImage
            source: iconImage
            colorization: 1.0
            colorizationColor: Theme.muted
            brightness: 1.0
        }
    }

    MouseArea {
        id: buttonMouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: profileMenu.open(root)
    }

    Components.AppToolTip {
        visible: root.tooltip.length > 0 && buttonMouseArea.containsMouse
        text: root.tooltip
    }

    Native.Menu {
        id: profileMenu
        minimumWidth: 160

        Instantiator {
            id: profileMenuItems
            model: root.profiles

            delegate: Native.MenuItem {
                required property int index
                required property var modelData
                text: String(modelData.label || "")
                onTriggered: root.profileSelected(String(modelData.id || ""))
            }

            onObjectAdded: function(index, object) {
                profileMenu.insertItem(index, object)
            }

            onObjectRemoved: function(index, object) {
                profileMenu.removeItem(object)
            }
        }
    }
}
