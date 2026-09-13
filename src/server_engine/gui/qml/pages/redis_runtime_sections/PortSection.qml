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
                text: Strings.t("port")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("use.this.when.port.6379.is.already.taken.or.when.you.want.redis.isolated.from.another.local.install")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

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
