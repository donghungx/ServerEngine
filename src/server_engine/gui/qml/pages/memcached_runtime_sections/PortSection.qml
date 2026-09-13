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
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                text: Strings.t("use.this.when.port.11211.is.already.taken.or.when.you.want.memcached.isolated.from.another.local.install")
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
                    text: pageRoot.memcachedPortDraft
                    onTextChanged: pageRoot.memcachedPortDraft = text
                    placeholderText: "11211"
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
            Components.AppButton {
                text: Strings.t("reload")
                onClicked: pageRoot.refreshMemcachedConfigDraft()
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var candidatePort = String(pageRoot.memcachedPortDraft || "").trim()
                    var ok = dashboardBridge.updateMemcachedRuntimePort(candidatePort)
                    pageRoot.memcachedConfigFeedback = dashboardBridge.memcachedRuntimeMessage
                    if (ok) {
                        pageRoot.memcachedPortLoaded = candidatePort
                        pageRoot.refreshMemcachedConfigDraft()
                    }
                }
            }
        }
    }
}
