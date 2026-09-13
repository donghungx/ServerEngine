import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
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
                text: String(pageRoot.mongodbRuntimeConfigPathText || bridge().activeMongodbConfigPath || "")
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: String(pageRoot.mongodbConfigDraft || "")
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                fontPixelSize: 12
                fontFamily: "Menlo"
                textColor: Theme.text
                readOnly: false
                onTextChanged: {
                    if (pageRoot) {
                        pageRoot.mongodbConfigDraft = text
                    }
                }
            }
        }

        footerLeft: Text {
            text: String(pageRoot.mongodbConfigFeedback || "")
            color: "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("reload")
                onClicked: pageRoot && pageRoot.refreshMongodbConfigDraft && pageRoot.refreshMongodbConfigDraft()
            }

            Components.AppButton {
                text: Strings.t("open.path")
                onClicked: bridge().revealInFinder && bridge().revealInFinder(bridge().activeMongodbConfigPath)
            }

            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var ok = bridge().saveActiveMongodbConfigContent && bridge().saveActiveMongodbConfigContent(pageRoot.mongodbConfigDraft)
                    pageRoot.mongodbConfigFeedback = String(bridge().mongodbRuntimeMessage || "")
                    if (ok) {
                        pageRoot && pageRoot.refreshMongodbConfigDraft && pageRoot.refreshMongodbConfigDraft()
                    }
                }
            }

            Components.AppButton {
                text: Strings.t("restore.original")
                onClicked: {
                    var ok = bridge().restoreActiveMongodbConfigOriginal && bridge().restoreActiveMongodbConfigOriginal()
                    pageRoot.mongodbConfigFeedback = String(bridge().mongodbRuntimeMessage || "")
                    if (ok) {
                        pageRoot && pageRoot.refreshMongodbConfigDraft && pageRoot.refreshMongodbConfigDraft()
                    }
                }
            }
        }
    }
}


