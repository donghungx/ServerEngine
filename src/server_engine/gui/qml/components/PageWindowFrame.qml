import QtQuick
import QtQuick.Layouts
import "../theme"

Rectangle {
    id: frame

    anchors.fill: parent
    color: Theme.surface

    property var moveWindow: null
    property int headerHeight: 96
    property int headerDragHeight: 24
    property int headerContentTopMargin: 0
    property int headerContentLeftMargin: 0
    property int headerContentRightMargin: 0
    property int headerContentBottomMargin: 6
    property int bodyMargins: 20

    default property alias bodyData: bodyHost.data
    property alias headerContent: headerHost.data

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: frame.headerHeight
            color: Theme.titleBar

            MouseArea {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: frame.headerDragHeight
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.ArrowCursor
                onPressed: function(mouse) {
                    if (frame.moveWindow) {
                        frame.moveWindow.startSystemMove()
                    }
                    mouse.accepted = true
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.border
            }

            Item {
                id: headerHost
                anchors.fill: parent
                anchors.topMargin: frame.headerContentTopMargin
                anchors.leftMargin: frame.headerContentLeftMargin
                anchors.rightMargin: frame.headerContentRightMargin
                anchors.bottomMargin: frame.headerContentBottomMargin
                clip: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surface

            Item {
                id: bodyHost
                anchors.fill: parent
                anchors.margins: frame.bodyMargins
                clip: true
            }
        }
    }
}

