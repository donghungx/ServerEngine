import QtQuick
import QtQuick.Effects
import "../theme"

Rectangle {
    id: root

    property string text: ""
    property string iconSource: "icons/lucide/check.svg"
    property bool success: true
    property bool danger: false

    visible: text.length > 0
    implicitHeight: 24
    implicitWidth: contentRow.implicitWidth + 18
    radius: 8
    border.width: 0
    color: danger
        ? Theme.danger
        : (success ? Theme.success : Theme.buttonNeutralBackground)

    function resolvedIconSource() {
        if (!iconSource || iconSource.length === 0) {
            return ""
        }
        if (iconSource.indexOf(":/") === 0
            || iconSource.indexOf("qrc:/") === 0
            || iconSource.indexOf("file:/") === 0) {
            return iconSource
        }
        if (iconSource.indexOf("icons/") === 0) {
            return "../" + iconSource
        }
        return iconSource
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 5

        Item {
            visible: root.iconSource.length > 0
            width: 12
            height: 12

            Image {
                id: badgeIconImage
                anchors.fill: parent
                visible: false
                source: root.resolvedIconSource()
                sourceSize.width: 12
                sourceSize.height: 12
                fillMode: Image.PreserveAspectFit
            }

            MultiEffect {
                anchors.fill: badgeIconImage
                source: badgeIconImage
                colorization: 1.0
                colorizationColor: "#ffffff"
                brightness: 1.0
            }
        }

        Text {
            text: root.text
            color: "#ffffff"
            font.pixelSize: 11
            font.weight: Font.Medium
            verticalAlignment: Text.AlignVCenter
        }
    }
}

