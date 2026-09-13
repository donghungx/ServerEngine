import QtQuick
import "../theme"

Item {
    required property string label
    required property int cellWidth

    width: cellWidth
    height: 40

    Text {
        anchors.fill: parent
        text: parent.label
        color: Theme.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
        elide: Text.ElideRight

        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignLeft

        leftPadding: 12
        rightPadding: 12
    }
}
