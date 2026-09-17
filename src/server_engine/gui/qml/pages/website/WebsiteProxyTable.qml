import QtQuick
import QtQuick.Controls
import "../../components" as Components
import "../../theme"

Item {
    id: tableRoot
    required property var pageRoot

    readonly property int bodyHeight: Math.max(0, tableRoot.height - headerCard.height - 14)
    anchors.fill: parent

    Rectangle {
        id: headerCard
        width: parent.width
        height: 40
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: Theme.border
        border.width: 1
        clip: true

        Row {
            width: parent.width
            height: parent.height
            spacing: 0

            Components.HeaderCell { label: "Domain"; cellWidth: 248 }
            Components.HeaderCell { label: "Target"; cellWidth: 300 }
            Components.HeaderCell { label: "SSL"; cellWidth: 100 }
            Components.HeaderCell { label: "Actions"; cellWidth: Math.max(0, parent.width - 648) }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerCard.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 14
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
        clip: true

        Components.AppScrollArea {
            anchors.fill: parent
            clipContent: true

            Item {
                width: parent.width
                height: Math.max(tableRoot.bodyHeight, proxyList.visible ? proxyList.contentHeight : emptyState.implicitHeight)

                ListView {
                    id: proxyList
                    width: parent.width
                    height: contentHeight
                    implicitHeight: contentHeight
                    model: tableRoot.pageRoot.dashboardBridge.proxyItems
                    visible: count > 0
                    interactive: false
                    clip: true

                    delegate: Column {
                        required property int index
                        required property var modelData
                        width: ListView.view.width

                        Rectangle {
                            width: parent.width
                            height: 70
                            color: "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 8
                                spacing: 0

                                Item {
                                    width: 248
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
                                                text: "↗"
                                                color: "white"
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                            }
                                        }

                                        Text {
                                            width: 196
                                            text: String(modelData.local_domain || "")
                                            color: Theme.accentStrong
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                Item {
                                    width: 300
                                    height: parent.height
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData.target || "")
                                        color: Theme.muted
                                        font.pixelSize: 12
                                        elide: Text.ElideMiddle
                                    }
                                }

                                Item {
                                    width: 100
                                    height: parent.height
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.ssl_enabled ? "On" : "Off"
                                        color: modelData.ssl_enabled ? Theme.websiteSslOnText : Theme.websiteSslOffText
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                }

                                Item {
                                    width: Math.max(0, parent.width - 648)
                                    height: parent.height
                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        Components.QuickActionButton {
                                            text: "Open"
                                            iconSource: "../icons/lucide/external-link.svg"
                                            tooltip: "Open website"
                                            onClicked: Qt.openUrlExternally((modelData.ssl_enabled ? "https://" : "http://") + modelData.local_domain)
                                        }
                                        Components.QuickActionButton {
                                            text: "Modify"
                                            iconSource: "../icons/lucide/settings.svg"
                                            tooltip: "Modify proxy"
                                            onClicked: {
                                                tableRoot.pageRoot.editingProxyId = String(modelData.id || "")
                                                tableRoot.pageRoot.editingProxyData = modelData
                                                tableRoot.pageRoot.addProxyOpen = true
                                            }
                                        }
                                        Components.QuickActionButton {
                                            text: "Delete"
                                            iconSource: "../icons/lucide/trash-2.svg"
                                            tooltip: "Delete proxy"
                                            danger: true
                                            onClicked: tableRoot.pageRoot.dashboardBridge.deleteProxy(modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.border
                        }
                    }
                }

                Column {
                    id: emptyState
                    anchors.centerIn: parent
                    visible: tableRoot.pageRoot.dashboardBridge.proxyItems.length === 0
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No proxy projects yet"
                        color: Theme.text
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Create your first proxy project with the Add Proxy Project button."
                        color: Theme.muted
                        font.pixelSize: 14
                    }
                }
            }
        }
    }
}
