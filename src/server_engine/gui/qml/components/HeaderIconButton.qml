import QtQuick
import QtQuick.Effects
import "../theme"
import "../i18n"

Rectangle {
    id: headerIconButton
    signal clicked()

    property string label: ""
    property string iconSource: ""
    property bool primary: false
    property color iconColor: primary ? Theme.accentStrong : Theme.muted

    width: Math.max(64, labelText.implicitWidth + 16)
    height: 48
    radius: Theme.radius
    color: mouseArea.containsMouse ? Theme.headerIconButtonHoverBackground : "transparent"
    opacity: enabled ? 1.0 : 0.45

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 2

        Image {
            id: headerIconSource
            width: 22
            height: 22
            sourceSize.width: 22
            sourceSize.height: 22
            anchors.horizontalCenter: parent.horizontalCenter
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: headerIconButton.iconSource.indexOf("icons/") === 0
                ? "../" + headerIconButton.iconSource
                : headerIconButton.iconSource
            visible: false
        }

        MultiEffect {
            width: 22
            height: 22
            anchors.horizontalCenter: parent.horizontalCenter
            source: headerIconSource
            colorization: 1.0
            colorizationColor: headerIconButton.iconColor
            brightness: 1.0
        }

        Text {
            id: labelText
            width: parent.width
            text: headerIconButton.label
            color: headerIconButton.primary ? Theme.accentStrong : Theme.muted
            font.pixelSize: 10
            font.weight: headerIconButton.primary ? Font.DemiBold : Font.Medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: headerIconButton.enabled
        onClicked: headerIconButton.clicked()
    }
}
