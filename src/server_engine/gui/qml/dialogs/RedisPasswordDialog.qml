import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    required property var pageRoot
    required property var dashboardBridge

    id: passwordWindow
    visible: pageRoot.passwordPopupOpen
    width: 560
    height: 260
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("redis.password")
    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: pageRoot.Window.window

    flags: Qt.Dialog
        | Qt.CustomizeWindowHint
        | Qt.WindowTitleHint
        | Qt.WindowCloseButtonHint

    onVisibleChanged: {
        if (visible) {
            passwordInput.text = dashboardBridge ? dashboardBridge.redisPassword : ""
            pageRoot.passwordFeedback = ""
            pageRoot.passwordFeedbackError = false
            if (dashboardBridge && dashboardBridge.clearRedisRuntimeFeedback) {
                dashboardBridge.clearRedisRuntimeFeedback()
            }
        } else {
            pageRoot.passwordPopupOpen = false
        }
    }

    Components.AppWindowFrame {
        title: Strings.t("redis.password")
        moveWindow: passwordWindow
        contentMargins: 20
        contentSpacing: 12

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: Strings.t("change.the.password.written.into.the.generated.redis.config.for.the.active.runtime")
                color: Theme.muted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: Strings.t("password")
                color: Theme.text
            }

            Components.AppTextField {
                id: passwordInput
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: Strings.t("leave.blank.to.disable.requirepass")
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("this.updates.the.generated.config.for") + (dashboardBridge ? dashboardBridge.activeRedisRuntimeLabel : "") + ". Redis must be restarted before the new password takes effect."
                color: Theme.muted
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Label {
                visible: text.length > 0
                Layout.fillWidth: true

                text: pageRoot.passwordFeedback.length > 0
                    ? pageRoot.passwordFeedback
                    : (dashboardBridge ? dashboardBridge.redisRuntimeMessage : "")

                color: pageRoot.passwordFeedback.length > 0
                    ? (pageRoot.passwordFeedbackError ? "#bb4d4d" : "#4aa94b")
                    : (dashboardBridge && dashboardBridge.redisRuntimeError ? "#bb4d4d" : "#4aa94b")

                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Item {
                Layout.fillHeight: true
            }
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                text: Strings.t("cancel")

                onClicked: {
                    pageRoot.passwordPopupOpen = false
                    pageRoot.passwordFeedback = ""
                    pageRoot.passwordFeedbackError = false
                    if (dashboardBridge && dashboardBridge.clearRedisRuntimeFeedback) {
                        dashboardBridge.clearRedisRuntimeFeedback()
                    }
                }
            }

            Components.AppButton {
                text: Strings.t("save.password")
                highlighted: true
                textColor: "white"

                onClicked: {
                    if (dashboardBridge && dashboardBridge.updateRedisPassword(passwordInput.text)) {
                        pageRoot.passwordFeedback = "Password saved. Restart Redis to apply the updated config."
                        pageRoot.passwordFeedbackError = false
                    } else {
                        pageRoot.passwordFeedback = dashboardBridge ? dashboardBridge.redisRuntimeMessage : ""
                        pageRoot.passwordFeedbackError = true
                    }
                }
            }
        }
    }
}
