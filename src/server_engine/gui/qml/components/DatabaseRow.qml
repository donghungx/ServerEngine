import QtQuick
import QtQuick.Controls
import "../theme"
import "../i18n"

Rectangle {
    id: root
    required property var rowData
    signal backupRequested(var rowData)
    signal importRequested(var rowData)
    signal dropRequested(var rowData)

    color: "transparent"
    border.width: 0

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 0
        spacing: 0

        Item {
            width: 330
            height: parent.height

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 24
                    height: 24
                    radius: Theme.radius
                    color: Theme.accentStrong

                    Text {
                        anchors.centerIn: parent
                        text: Strings.t("db")
                        color: "white"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                Column {
                    spacing: 4
                    width: 330 - 24 - 12

                    Text {
                        text: rowData.name
                        color: Theme.text
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: rowData.engine + " " + rowData.runtime
                        color: Theme.muted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }
        }

        Item {
            width: 140
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: rowData.engine
                color: Theme.text
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        Item {
            width: Math.max(0, parent.width - 330 - 140)
            height: parent.height

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                QuickActionButton {
                    text: Strings.t("backup")
                    iconSource: "../icons/lucide/download.svg"
                    onClicked: root.backupRequested(root.rowData)
                }

                QuickActionButton {
                    text: Strings.t("import")
                    iconSource: "../icons/lucide/database-import.svg"
                    onClicked: root.importRequested(root.rowData)
                }

                QuickActionButton {
                    text: Strings.t("drop")
                    iconSource: "../icons/lucide/trash-2.svg"
                    danger: true
                    onClicked: root.dropRequested(root.rowData)
                }
            }
        }
    }
}
