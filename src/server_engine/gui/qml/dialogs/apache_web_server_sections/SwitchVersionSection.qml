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
                text: "Choose which packaged Apache runtime should be active."
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
                        model: pageRoot.apacheRuntimeModel

                        delegate: Rectangle {
                            required property int index
                            property var runtimeItem: pageRoot.apacheRuntimeModel[index]
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
                                    onClicked: dashboardBridge.saveWebServerRuntimeSettings(
                                        "apache",
                                        runtimeItem.id,
                                        String(dashboardBridge.settingsNginxRuntime || "")
                                    )
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
