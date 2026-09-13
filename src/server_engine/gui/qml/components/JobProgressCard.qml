import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../theme"
import "." as Components

Item {
    id: root

    property string title: ""
    property string detail: ""
    property int progress: 0
    property bool cancelable: false
    property bool busy: false

    signal cancelRequested()

    width: 240
    height: 22
    visible: busy

    RowLayout {
        anchors.fill: parent
        spacing: 2

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            Text {
                text: root.title
                color: Theme.text
                font.pixelSize: 11
                font.weight: Font.Normal
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                clip: true
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 4
                    radius: 2
                    color: Theme.border
                    clip: true

                    Rectangle {
                        width: parent.width * (Math.max(0, Math.min(root.progress, 100)) / 100.0)
                        height: parent.height
                        radius: 1.5
                        color: Theme.accentStrong

                        Behavior on width {
                            NumberAnimation { duration: 120 }
                        }
                    }
                }

            }
        }

        Components.QuickActionButton {
            visible: root.cancelable && root.busy
            text: ""
            iconSource: "icons/lucide/x.svg"
            tooltip: "Cancel"
            onClicked: root.cancelRequested()
        }
    }
}
