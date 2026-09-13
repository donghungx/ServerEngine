import QtQuick
import QtQuick.Layouts
import "../theme"
import "." as Components

Rectangle {
    id: root

    required property bool checked
    property bool itemEnabled: true
    property bool alternating: false
    property string title: ""
    property string description: ""
    property int checkboxColumnWidth: 32
    property int titleColumnWidth: 220
    property int descriptionColumnWidth: 0

    signal toggled(bool checked)

    width: parent ? parent.width : 300
    height: 24
    color: alternating ? Theme.surfaceAlt : Theme.surface
    opacity: itemEnabled ? 1.0 : 0.55
    clip: true

    MouseArea {
        anchors.fill: parent
        enabled: root.itemEnabled
        cursorShape: Qt.ArrowCursor
        onClicked: root.toggled(!root.checked)
    }

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8

        Components.AppCheckBox {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.checkboxColumnWidth
            checked: root.checked
            enabled: root.itemEnabled
            onToggled: root.toggled(checked)
        }

        Text {
            id: titleText
            Layout.preferredWidth: root.titleColumnWidth
            Layout.minimumWidth: root.titleColumnWidth
            Layout.maximumWidth: root.titleColumnWidth
            text: root.title
            color: Theme.text
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
        }

        Text {
            id: descriptionText
            Layout.preferredWidth: root.descriptionColumnWidth > 0 ? root.descriptionColumnWidth : 0
            Layout.minimumWidth: root.descriptionColumnWidth > 0 ? root.descriptionColumnWidth : 0
            Layout.maximumWidth: root.descriptionColumnWidth > 0 ? root.descriptionColumnWidth : Number.POSITIVE_INFINITY
            Layout.fillWidth: root.descriptionColumnWidth <= 0
            text: root.description
            color: Theme.muted
            font.pixelSize: 11
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
        }
    }
}
