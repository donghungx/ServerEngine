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

            Text {
                Layout.fillWidth: true
                text: dashboardBridge.activeRedisConfigPath
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: pageRoot.redisConfigDraft
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                fontPixelSize: 12
                fontFamily: "Menlo"
                textColor: Theme.text
                readOnly: false
                onTextChanged: {
                    if (pageRoot) {
                        pageRoot.redisConfigDraft = text
                    }
                }
            }
        }

        footerLeft: Text {
            text: pageRoot.redisConfigFeedback
            color: dashboardBridge.redisRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton { text: Strings.t("reload"); onClicked: pageRoot.refreshRedisConfigDraft() }
            Components.AppButton { text: Strings.t("open.path"); onClicked: dashboardBridge.revealInFinder(dashboardBridge.activeRedisConfigPath) }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var ok = dashboardBridge.saveActiveRedisConfigContent(pageRoot.redisConfigDraft)
                    pageRoot.redisConfigFeedback = dashboardBridge.redisRuntimeMessage
                    if (ok) {
                        pageRoot.refreshRedisConfigDraft()
                    }
                }
            }

            Components.AppButton {
                text: Strings.t("restore.original")
                onClicked: {
                    var ok = dashboardBridge.restoreActiveRedisConfigOriginal()
                    pageRoot.redisConfigFeedback = dashboardBridge.redisRuntimeMessage
                    if (ok) {
                        pageRoot.refreshRedisConfigDraft()
                    }
                }
            }
        }
    }
}
