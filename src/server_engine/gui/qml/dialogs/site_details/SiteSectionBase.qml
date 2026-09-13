import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../i18n"

Item {
    property var siteData: ({})
    required property string sectionTitle
    property string sectionDescription: "Section shell is ready. Content can be added here next."

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        Label {
            text: sectionTitle
            color: Theme.text
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }

        Label {
            text: sectionDescription
            color: Theme.muted
            font.pixelSize: 13
        }

        RowLayout {
            spacing: 10

            Rectangle {
                width: 88
                height: 30
                radius: 8
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Strings.t("status")
                    color: Theme.muted
                    font.pixelSize: 12
                }
            }

            Label {
                text: siteData.status ? siteData.status : "Unknown"
                color: Theme.text
                font.pixelSize: 13
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: "#fbfbfc"
            border.color: Theme.border
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Label {
                    text: Strings.t("content.placeholder")
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Strings.t("this.section.is.prepared.send.the.content.for") + sectionTitle + "' and I will wire it into this panel."
                    color: Theme.muted
                    font.pixelSize: 13
                }
            }
        }
    }
}
