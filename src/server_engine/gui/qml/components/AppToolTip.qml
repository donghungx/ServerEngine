import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "../theme"

ToolTip {
    id: root

    delay: 450

    background: Rectangle {
        id: tooltipSurface
        radius: 6
        color: Theme.toolTipBackground
        border.width: 0

        RectangularShadow {
            anchors.fill: tooltipSurface
            color: Theme.toolTipShadow
            blur: 18
            spread: 0
            offset.x: 0
            offset.y: 2
            z: -1
        }
    }

    contentItem: Text {
        text: root.text
        color: Theme.toolTipText
        font.pixelSize: 11
        font.weight: Font.Medium
    }
}
