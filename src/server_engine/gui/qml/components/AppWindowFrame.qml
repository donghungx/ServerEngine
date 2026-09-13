import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "../i18n"

Rectangle {
    id: frame

    property string title: ""
    property var moveWindow: null

    property int contentMargins: 12
    property int contentLeftMargin: contentMargins
    property int contentRightMargin: contentMargins
    property int contentTopMargin: contentMargins
    property int contentBottomMargin: contentMargins
    property int contentSpacing: 0
    property int footerRightMargin: contentMargins
    property int footerBottomMargin: contentMargins

    default property alias contentData: contentHost.data
    property alias footerLeft: footerLeftHost.data
    property alias footerRight: footerRightHost.data

    anchors.fill: parent
    color: Theme.surface

    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.ArrowCursor

        onPressed: function(mouse) {
            if (frame.moveWindow) {
                frame.moveWindow.startSystemMove()
            }

            mouse.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 80
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: frame.title
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: frame.contentLeftMargin
            Layout.rightMargin: frame.contentRightMargin
            Layout.topMargin: 2
            Layout.bottomMargin: footerRow.visible ? frame.contentSpacing : frame.contentBottomMargin

            Item {
                id: contentHost
                anchors.fill: parent
            }
        }

        Item {
            id: footerRow
            Layout.fillWidth: true
            Layout.leftMargin: frame.contentMargins
            Layout.rightMargin: frame.footerRightMargin
            Layout.bottomMargin: frame.footerBottomMargin
            Layout.preferredHeight: Math.max(
                footerLeftHost.childrenRect.height,
                footerRightHost.childrenRect.height
            )
            visible: frame.hasVisibleFooterContent(footerLeftHost) || frame.hasVisibleFooterContent(footerRightHost)

            Row {
                id: footerRightHost
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
            }

            Item {
                id: footerLeftHost
                anchors.left: parent.left
                anchors.right: footerRightHost.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: childrenRect.height
            }
        }
    }

    function hasVisibleFooterContent(item) {
        if (!item || !item.children) {
            return false
        }
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (child && child.visible !== false) {
                return true
            }
        }
        return false
    }
}
