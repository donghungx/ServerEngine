import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"

ScrollView {
    id: root
    property var phpRuntime: ({})
    property string sectionTitle: ""
    property string sectionDescription: ""
    property bool showSectionHeader: true
    default property alias sectionContent: contentColumn.data

    clip: true

    ColumnLayout {
        id: contentColumn
        width: root.availableWidth
        spacing: 18

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.showSectionHeader
            spacing: 6

            Label {
                text: root.sectionTitle
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                text: root.sectionDescription
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }
}
