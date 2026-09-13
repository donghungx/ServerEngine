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
                text: Strings.t("apache.modules")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: "Choose which Apache modules should be enabled."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Components.CheckableDescriptionList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                headerLeftText: "Name"
                headerRightText: Strings.t("description")
                model: pageRoot.apacheModulesDraft
                onToggled: function(index, nextChecked) {
                    pageRoot.apacheModulesDraft[index].enabled = nextChecked
                }
            }
        }

        footerLeft: Text {
            text: dashboardBridge.appSettingsMessage
            color: dashboardBridge.appSettingsError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                text: Strings.t("reload")
                onClicked: {
                    if (runtimeWindow && runtimeWindow.refreshApacheDrafts) {
                        runtimeWindow.refreshApacheDrafts()
                    }
                }
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var selectedModules = []
                    for (var i = 0; i < pageRoot.apacheModulesDraft.length; i++) {
                        if (pageRoot.apacheModulesDraft[i].enabled) {
                            selectedModules.push(pageRoot.apacheModulesDraft[i].name)
                        }
                    }
                    dashboardBridge.saveApacheModules(selectedModules)
                }
            }
        }
    }
}
