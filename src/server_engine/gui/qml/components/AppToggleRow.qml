import QtQuick
import QtQuick.Layouts
import "../theme"
import "." as Components

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool checked: false
    signal toggled(bool checked)

    Layout.fillWidth: true
    implicitHeight: subtitle.length > 0 ? 44 : 32

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Components.AppSwitch {
            checked: root.checked
            Layout.alignment: Qt.AlignVCenter
            onToggled: function(nextChecked) {
                root.checked = nextChecked
                root.toggled(nextChecked)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: subtitle.length > 0 ? 2 : 0

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.Normal
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                color: Theme.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
