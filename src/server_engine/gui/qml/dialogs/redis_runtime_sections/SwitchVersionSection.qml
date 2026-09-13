import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.surfaceAlt
                    border.color: Theme.border
                    border.width: 1
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: dashboardBridge.redisRuntimeItems

                        delegate: Rectangle {
                            required property int index
                            property var runtimeItem: dashboardBridge.redisRuntimeItems[index]
                            width: parent.width
                            height: 72
                            radius: Theme.radius
                            color: Theme.surface
                            border.color: runtimeItem.status === "Active" ? Theme.accentStrong : Theme.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text {
                                        text: runtimeItem.label
                                        color: Theme.text
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: runtimeItem.home
                                        color: Theme.muted
                                        font.pixelSize: 12
                                        elide: Text.ElideMiddle
                                        width: parent.width
                                    }
                                }

                                Components.AppButton {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    text: runtimeItem.status === "Active" ? "Active" : "Use Runtime"
                                    enabled: runtimeItem.status !== "Active"
                                    highlighted: runtimeItem.status !== "Active"
                                    textColor: runtimeItem.status !== "Active" ? "white" : Theme.text
                                    onClicked: dashboardBridge.saveRedisRuntimeSelection(runtimeItem.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
