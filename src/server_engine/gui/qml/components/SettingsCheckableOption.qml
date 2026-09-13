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
    property int titleWidth: 176
    property int contentLeftPadding: 24
    property int checkboxWidth: 14
    property int rowSpacing: 8
    property int descriptionSpacing: 3

    default property alias descriptionElement: descriptionHost.data

    signal toggled(bool checked)

    Layout.fillWidth: true
    spacing: 0
    opacity: itemEnabled ? 1.0 : 0.55

    TapHandler {
        enabled: root.itemEnabled && root.clickable
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: {
            root.checked = !root.checked
            root.toggled(root.checked)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.rowSpacing

        Item {
            Layout.preferredWidth: root.titleWidth
            Layout.minimumWidth: root.titleWidth
            Layout.maximumWidth: root.titleWidth
        }

        Item {
            Layout.preferredWidth: root.contentLeftPadding
            Layout.minimumWidth: root.contentLeftPadding
            Layout.maximumWidth: root.contentLeftPadding
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.rowSpacing

            Components.AppCheckBox {
                Layout.preferredWidth: root.checkboxWidth
                Layout.alignment: Qt.AlignVCenter
                checked: root.checked
                enabled: root.itemEnabled
                onToggled: function(nextChecked) {
                    root.checked = nextChecked
                    root.toggled(nextChecked)
                }
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
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.rowSpacing
        visible: descriptionHost.children.length > 0 || root.description.length > 0

        Item {
            Layout.preferredWidth: root.titleWidth + 22
            Layout.minimumWidth: root.titleWidth + 22
            Layout.maximumWidth: root.titleWidth + 22
        }

        Item {
            Layout.preferredWidth: root.contentLeftPadding
            Layout.minimumWidth: root.contentLeftPadding
            Layout.maximumWidth: root.contentLeftPadding
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
