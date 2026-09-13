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
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (pageRoot && pageRoot.dashboardBridge) {
            return pageRoot.dashboardBridge
        }
        return ({})
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
                text: Strings.t("error.log")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("runtime.error.log.output.for.the.active.database.version")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Components.AppScrollEditor {
                id: fullLogText
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: String(bridge().mongodbRuntimeLog || "").length > 0 ? String(bridge().mongodbRuntimeLog || "") : "No runtime log yet."
                textColor: Theme.text
                fontPixelSize: 12
                fontFamily: "Menlo"
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                readOnly: true
                selectByMouse: true
            }
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                text: Strings.t("refresh")
                onClicked: bridge().refreshMongodbRuntime && bridge().refreshMongodbRuntime()
            }
        }
    }
}


