import QtQuick
import "../theme"

Item {
    id: root
    implicitWidth: 28
    implicitHeight: 16

    property bool checked: false
    property bool autoToggle: true
    signal clicked()
    signal toggled(bool checked)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.switchTrackChecked : Theme.switchTrackUnchecked

        Rectangle {
            width: 12
            height: 12
            radius: 6
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: Theme.switchThumb
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            var nextChecked = !root.checked
            if (root.autoToggle) {
                root.checked = nextChecked
            }
            root.toggled(nextChecked)
            root.clicked()
        }
    }
}
