import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"

Item {
    property var pageRoot: ({})
    property var dashboardBridge: ({})
    property var runtimeWindow

    Column {
        anchors.fill: parent
        spacing: 14
        Rectangle {
            width: parent.width
            height: 120
            radius: Theme.radius
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            Text {
                anchors.fill: parent
                anchors.margins: 16
                text: pageRoot.runtimeSectionDescription(pageRoot.runtimePopupSection)
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }
    }
}
