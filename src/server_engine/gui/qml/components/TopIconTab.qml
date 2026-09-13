import QtQuick
import QtQuick.Effects
import "../theme"
import "../i18n"

Rectangle {
    id: root
    signal clicked()

    property string label: ""
    property string iconSource: ""
    property bool selected: false

    implicitWidth: Math.max(56, tabLabel.implicitWidth + 20)
    width: implicitWidth
    height: 56
    radius: Theme.radius + 2
    color: selected ? Theme.topIconTabSelectedBackground : "transparent"

    Column {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        Rectangle {
            width: 24
            height: 24
            anchors.horizontalCenter: parent.horizontalCenter
            color: "transparent"

            Image {
                id: iconImage
                anchors.centerIn: parent
                width: 24
                height: 24
                sourceSize.width: 24
                sourceSize.height: 24
                fillMode: Image.PreserveAspectFit
                smooth: true
                source: root.iconSource
                visible: false
            }

            MultiEffect {
                anchors.centerIn: parent
                width: 24
                height: 24
                source: iconImage
                colorization: 1.0
                colorizationColor: root.selected ? Theme.accentStrong : Theme.muted
                brightness: 1.0
            }
        }

        Text {
            id: tabLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: root.selected ? Theme.accentStrong : Theme.muted
            font.pixelSize: 12
            font.weight: Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
