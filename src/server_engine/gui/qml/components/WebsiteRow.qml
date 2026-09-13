import QtQuick
import QtQuick.Controls
import "../theme"
import "../i18n"

Rectangle {
    id: root
    required property var rowData
    required property var dashboardBridge
    signal siteSelected()
    signal cliRequested()
    signal modifyRequested()
    signal deleteRequested()

    property string sslStatus: rowData.ssl === "Not Set" ? "Off" : "On"

    function projectFolderUrl() {
        return "file://" + encodeURI(rowData.project_path)
    }

    color: "transparent"
    border.color: Theme.border
    border.width: 0

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 0
        spacing: 0

        Item {
            width: 220
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
                        text: Strings.t("n")
                        color: "white"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }

                Item {
                    width: 220 - 24 - 12
                    height: textColumn.implicitHeight

                    Column {
                        id: textColumn
                        spacing: 4
                        anchors.left: parent.left
                        anchors.right: parent.right

                        Text {
                            id: domainText
                            text: rowData.name
                            color: Theme.accentStrong
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: rowData.project_path
                            color: Theme.muted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.siteSelected()
                    }
                }
            }
        }

        Item {
            width: 92
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: rowData.php
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Item {
            width: 100
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: sslStatus
                color: sslStatus === "On" ? Theme.websiteSslOnText : Theme.websiteSslOffText
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Item {
            width: Math.max(0, parent.width - 220 - 92 - 100)
            height: parent.height

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                QuickActionButton {
                    text: Strings.t("open.path")
                    iconSource: "../icons/lucide/folder-open.svg"
                    tooltip: Strings.t("open.path")
                    onClicked: Qt.openUrlExternally(projectFolderUrl())
                }

                QuickActionButton {
                    text: Strings.t("cli")
                    iconSource: "../icons/lucide/terminal.svg"
                    tooltip: Strings.t("open.cli")
                    onClicked: root.cliRequested()
                }

                QuickActionButton {
                    text: Strings.t("open.site")
                    iconSource: "../icons/lucide/external-link.svg"
                    tooltip: Strings.t("open.site")
                    onClicked: Qt.openUrlExternally(rowData.browse_url)
                }

                QuickActionButton {
                    text: Strings.t("modify")
                    iconSource: "../icons/lucide/settings.svg"
                    onClicked: root.modifyRequested()
                }

                QuickActionButton {
                    text: Strings.t("remove")
                    iconSource: "../icons/lucide/trash-2.svg"
                    danger: true
                    onClicked: root.deleteRequested()
                }
            }
        }
    }
}
