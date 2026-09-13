import QtQuick
import "../theme"

Rectangle {
    required property string label
    required property bool primary

    radius: 10
    color: primary ? Theme.accentStrong : Theme.surfaceAlt
    border.color: primary ? Theme.accentStrong : Theme.borderStrong
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: parent.label
        color: parent.primary ? "white" : Theme.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
}
