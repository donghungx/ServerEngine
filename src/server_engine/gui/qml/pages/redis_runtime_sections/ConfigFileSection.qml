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
        contentMargins: 0
        contentSpacing: 10
        footerRightMargin: 0
        footerBottomMargin: 0

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("configuration")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("the.app.generates.a.dedicated.config.file.for.the.active.runtime.version.before.startup")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

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
