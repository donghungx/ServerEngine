import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow
    anchors.fill: parent

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Column {
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: dashboardBridge.mailpitRuntimeItems

                        delegate: Rectangle {
                            required property int index
                            property var runtimeItem: dashboardBridge.mailpitRuntimeItems[index]
                            width: parent.width
                            height: 72
                            radius: Theme.radius
                            color: "transparent"
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
                                    visible: runtimeItem.status !== "Active"
                                    onClicked: dashboardBridge.activateRuntime("mailpit", runtimeItem.id, false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
