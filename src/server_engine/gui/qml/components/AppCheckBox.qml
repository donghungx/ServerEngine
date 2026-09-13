import QtQuick
import QtQuick.Effects
import "../theme"

Item {
    id: root
    implicitWidth: contentRow.implicitWidth
    implicitHeight: contentRow.implicitHeight

    property alias text: label.text
    property bool checked: false
    signal toggled(bool checked)

    Row {
        id: contentRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Rectangle {
            width: 16
            height: 16
            radius: 6
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? Theme.checkboxBackgroundChecked : Theme.checkboxBackgroundUnchecked

            Item {
                anchors.centerIn: parent
                width: 12
                height: 12
                visible: root.checked

                Image {
                    id: checkIconImage
                    anchors.fill: parent
                    source: "../icons/lucide/check.svg"
                    sourceSize.width: 12
                    sourceSize.height: 12
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MultiEffect {
                    anchors.fill: checkIconImage
                    source: checkIconImage
                    colorization: 1.0
                    colorizationColor: Theme.checkboxCheckmark
                    brightness: 1.0
                }
            }
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.pixelSize: 12
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            console.log(
                "[AppCheckBox] clicked text=",
                String(label.text),
                "before=",
                String(root.checked)
            )
            root.checked = !root.checked
            console.log(
                "[AppCheckBox] toggled text=",
                String(label.text),
                "after=",
                String(root.checked)
            )
            root.toggled(root.checked)
        }
    }
}
