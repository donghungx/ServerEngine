import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"
        contentMargins: 0
        contentSpacing: 10
        footerRightMargin: 0
        footerBottomMargin: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("switch.version")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("choose.which.packaged.memcached.runtime.should.be.active")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Column {
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: dashboardBridge.memcachedRuntimeItems

                        delegate: Rectangle {
                            required property int index
                            property var runtimeItem: dashboardBridge.memcachedRuntimeItems[index]
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
                                    onClicked: dashboardBridge.saveMemcachedRuntimeSelection(runtimeItem.id)
                                    visible: runtimeItem.status !== "Active"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
