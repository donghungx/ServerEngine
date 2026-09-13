
import QtQuick
import QtQuick.Layouts
import "../theme"

ColumnLayout {
    id: root

    property string title: ""
    property string description: ""
    property int titleWidth: 208
    property int rowSpacing: 8
    property int descriptionSpacing: 6

    default property alias contentData: controlHost.data
    property alias descriptionElement: descriptionHost.data

    Layout.fillWidth: true
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: root.rowSpacing

        Text {
            Layout.preferredWidth: root.titleWidth
            Layout.minimumWidth: root.titleWidth
            Layout.maximumWidth: root.titleWidth
            text: root.title
            color: Theme.text
            font.pixelSize: 13
            font.weight: Font.Medium
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            id: controlHost
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: childrenRect.height
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.rowSpacing
        visible: descriptionHost.children.length > 0 || root.description.length > 0

        Item {
            Layout.preferredWidth: root.titleWidth
            Layout.minimumWidth: root.titleWidth
            Layout.maximumWidth: root.titleWidth
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.descriptionSpacing

            ColumnLayout {
                id: descriptionHost
                Layout.fillWidth: true
                spacing: root.descriptionSpacing
                visible: children.length > 0
            }

            Text {
                visible: descriptionHost.children.length === 0 && root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                color: Theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }
}
