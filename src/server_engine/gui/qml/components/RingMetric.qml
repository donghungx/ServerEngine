import QtQuick
import QtQuick.Shapes
import "../theme"

Item {
    required property string title
    required property string value
    required property string detail
    required property string caption
    required property real percent

    implicitWidth: 220
    implicitHeight: 250

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20

        Item {
            width: 170
            height: 170

            Rectangle {
                anchors.centerIn: parent
                width: 156
                height: 156
                radius: 78
                color: "transparent"
                border.color: Theme.ringMetricTrackBorder
                border.width: 10
            }

            Shape {
                anchors.fill: parent

                ShapePath {
                    strokeColor: Theme.accentStrong
                    strokeWidth: 10
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 85
                    startY: 12

                    PathAngleArc {
                        centerX: 85
                        centerY: 85
                        radiusX: 73
                        radiusY: 73
                        startAngle: -90
                        sweepAngle: 360 * (percent / 100.0)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: value
                color: Theme.text
                font.pixelSize: 34
                font.weight: Font.Bold
            }
        }

        Column {
            width: 220
            spacing: 8

            Text {
                text: title
                color: Theme.text
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }

            Text {
                text: detail
                color: Theme.text
                font.pixelSize: 14
            }

            Text {
                text: caption
                color: Theme.muted
                font.pixelSize: 13
            }
        }
    }
}
