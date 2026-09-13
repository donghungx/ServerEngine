import QtQuick
import QtQuick.Layouts
import "../theme"
import "." as Components

ColumnLayout {
    id: root

    required property string selectedValue
    property bool itemEnabled: true
    property bool clickable: true
    property string title: ""
    property string description: ""
    property var model: []
    property string labelRole: "label"
    property string valueRole: "value"
    property int titleWidth: 208
    property int radioWidth: 14
    property int rowSpacing: 8
    property int optionSpacing: 4
    property int descriptionSpacing: 2

    signal selected(string value)

    Layout.fillWidth: true
    spacing: 0
    opacity: itemEnabled ? 1.0 : 0.55

    RowLayout {
        Layout.fillWidth: true
        spacing: root.rowSpacing
        Layout.alignment: Qt.AlignTop

        Text {
            id: titleText
            Layout.preferredWidth: root.titleWidth
            Layout.alignment: Qt.AlignTop
            text: root.title
            color: Theme.text
            font.pixelSize: 13
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignRight
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.model

                delegate: Components.AppRadioButton {
                    required property int index
                    property var itemData: root.model[index]
                    text: String((itemData && itemData[root.labelRole] !== undefined) ? itemData[root.labelRole] : itemData)
                    checked: String((itemData && itemData[root.valueRole] !== undefined) ? itemData[root.valueRole] : itemData) === String(root.selectedValue || "")

                    onClicked: {
                        var nextValue = String((itemData && itemData[root.valueRole] !== undefined) ? itemData[root.valueRole] : itemData)
                        root.selectedValue = nextValue
                        root.selected(nextValue)
                    }
                }
            }

            Text {
                id: descriptionText
                Layout.fillWidth: true
                text: root.description
                color: Theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }
}

