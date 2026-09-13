import QtQuick
import "../theme"
import "../i18n"

Item {
    id: root
    implicitWidth: radioRow.implicitWidth
    implicitHeight: radioRow.implicitHeight

    property string text: ""
    property bool checked: false
    signal clicked()

    Row {
        id: radioRow
        spacing: 8
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            width: 14
            height: 14
            radius: 7
            border.width: 1
            border.color: root.checked ? Theme.accentStrong : Theme.border
            color: Theme.surface
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: Theme.accentStrong
                visible: root.checked
            }
        }

        Text {
            text: root.text
            color: Theme.text
            font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
