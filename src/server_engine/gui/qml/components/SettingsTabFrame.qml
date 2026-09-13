import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"

Rectangle {
    id: frame

    property int contentMargins: 12
    property int contentSpacing: 0
    property int footerRightMargin: contentMargins
    property int footerBottomMargin: contentMargins

    default property alias contentData: contentHost.data
    property alias footerLeft: footerLeftHost.data
    property alias footerRight: footerRightHost.data

    anchors.fill: parent
    color: Theme.surface

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: frame.contentMargins
            Layout.rightMargin: frame.contentMargins
            Layout.topMargin: frame.contentMargins
            Layout.bottomMargin: footerRow.visible ? frame.contentSpacing : frame.contentMargins
            spacing: 0

            ColumnLayout {
                id: contentHost
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
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
            visible: footerLeftHost.children.length > 0 || footerRightHost.children.length > 0

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
}
