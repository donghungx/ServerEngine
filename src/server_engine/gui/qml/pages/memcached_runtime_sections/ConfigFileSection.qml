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
                text: dashboardBridge.activeMemcachedConfigPath
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: pageRoot.memcachedConfigDraft
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                fontPixelSize: 12
                fontFamily: "Menlo"
                textColor: Theme.text
                readOnly: false
                onTextChanged: {
                    if (pageRoot) {
                        pageRoot.memcachedConfigDraft = text
                    }
                }
            }
        }

        footerLeft: Text {
            text: pageRoot.memcachedConfigFeedback
            color: dashboardBridge.memcachedRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton { text: Strings.t("reload"); onClicked: pageRoot.refreshMemcachedConfigDraft() }
            Components.AppButton { text: Strings.t("open.path"); onClicked: dashboardBridge.revealInFinder(dashboardBridge.activeMemcachedConfigPath) }
            Components.AppButton {
                text: Strings.t("restore.original")
                onClicked: {
                    var ok = dashboardBridge.restoreActiveMemcachedConfigOriginal()
                    pageRoot.memcachedConfigFeedback = dashboardBridge.memcachedRuntimeMessage
                    if (ok) {
                        pageRoot.refreshMemcachedConfigDraft()
                    }
                }
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var ok = dashboardBridge.saveActiveMemcachedConfigContent(pageRoot.memcachedConfigDraft)
                    pageRoot.memcachedConfigFeedback = dashboardBridge.memcachedRuntimeMessage
                    if (ok) {
                        pageRoot.refreshMemcachedConfigDraft()
                    }
                }
            }
        }
    }
}
