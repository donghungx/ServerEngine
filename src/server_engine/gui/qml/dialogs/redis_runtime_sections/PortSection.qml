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

            Row {
                spacing: 10

                Text {
                    text: Strings.t("port")
                    color: Theme.muted
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Components.AppTextField {
                    width: 120
                    text: pageRoot.redisPortDraft
                    onTextChanged: pageRoot.redisPortDraft = text
                    placeholderText: "6379"
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
            Components.AppButton {
                text: Strings.t("reload")
                onClicked: pageRoot.refreshRedisConfigDraft()
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var candidatePort = String(pageRoot.redisPortDraft || "").trim()
                    var ok = dashboardBridge.updateRedisRuntimePort(candidatePort)
                    pageRoot.redisConfigFeedback = dashboardBridge.redisRuntimeMessage
                    if (ok) {
                        pageRoot.redisPortLoaded = candidatePort
                        pageRoot.refreshRedisConfigDraft()
                    }
                }
            }
        }
    }
}
