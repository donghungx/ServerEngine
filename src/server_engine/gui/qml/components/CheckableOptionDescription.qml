import QtQuick
import QtQuick.Layouts
import "../theme"
import "." as Components

ColumnLayout {
    id: root

    required property bool checked
    property bool itemEnabled: true
    property bool clickable: true
    property string title: ""
    property string description: ""
    property int checkboxWidth: 24
    property int titleSpacing: 8
    property int descriptionIndent: 22
    property int descriptionSpacing: 6

    default property alias descriptionElement: descriptionHost.data

    signal toggled(bool checked)

    Layout.fillWidth: true
    spacing: 0
    opacity: itemEnabled ? 1.0 : 0.55

    MouseArea {
        anchors.fill: parent
        enabled: root.itemEnabled && root.clickable
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled(!root.checked)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.titleSpacing

        Components.AppCheckBox {
            Layout.preferredWidth: root.checkboxWidth
            checked: root.checked
            enabled: root.itemEnabled
            onToggled: root.toggled(checked)
        }

        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.text
            font.pixelSize: 13
            font.weight: Font.Medium
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.titleSpacing
        visible: descriptionHost.children.length > 0 || root.description.length > 0

        Item {
            Layout.preferredWidth: root.descriptionIndent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.descriptionSpacing

            ColumnLayout {
                id: descriptionHost
                Layout.fillWidth: true
                spacing: root.descriptionSpacing
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
