import QtQuick
import QtQuick.Effects
import "." as Components
import "../theme"
import "../i18n"

Rectangle {
    id: statusTextButton
    signal clicked()

    property string label: ""
    property string iconSource: ""
    property bool active: false
    property string tooltip: ""

    width: contentRow.implicitWidth + 18
    height: 24
    radius: 8
    color: active
        ? Theme.buttonNeutralBackground
        : (buttonMouseArea.containsMouse ? Theme.buttonNeutralBackground : "transparent")
    border.width: 0

    Row {
        id: contentRow
        anchors.centerIn: parent
        height: parent.height
        spacing: 5

        Item {
            id: buttonIconHost
            width: statusTextButton.iconSource.length > 0 ? 12 : 0
            height: parent.height

            Image {
                id: buttonIconImage
                anchors.fill: parent
                visible: statusTextButton.iconSource.length > 0
                source: statusTextButton.iconSource
                sourceSize.width: 12
                sourceSize.height: 12
                fillMode: Image.PreserveAspectFit
            }

            MultiEffect {
                anchors.fill: buttonIconImage
                source: buttonIconImage
                colorization: 1.0
                colorizationColor: Theme.text
                brightness: 1.0
                visible: buttonIconImage.visible
            }
        }

        Text {
            id: labelText
            text: statusTextButton.label
            height: parent.height
            color: Theme.text
            font.pixelSize: 11
            font.weight: Font.Medium
            verticalAlignment: Text.AlignVCenter
        }
    }

    MouseArea {
        id: buttonMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: statusTextButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (statusTextButton.enabled) {
                statusTextButton.clicked()
            }
        }
    }

    Components.AppToolTip {
        visible: statusTextButton.tooltip.length > 0 && buttonMouseArea.containsMouse
        delay: 400
        text: statusTextButton.tooltip
    }
}
