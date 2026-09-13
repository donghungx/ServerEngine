import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot: ({})
    property var dashboardBridge: ({})
    property var runtimeWindow

    function bridge() {
        return dashboardBridge || ({})
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("data.directory")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("the.app.will.create.and.use.this.data.directory.for.the.active.runtime")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: String(bridge().activePostgresqlDataDir || "")
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                text: Strings.t("open.path")
                onClicked: Qt.openUrlExternally(pageRoot.folderUrl(String(bridge().activePostgresqlDataDir || "")))
            }
        }
    }
}


