import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components" as Components
import "../theme"
import "../i18n"

Components.AppDialogWindow {
    id: root
    required property var window
    required property var appSettingsWindow
    visible: window.defaultPortsConfirmOpen
    width: 520
    height: 220
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("confirm.default.ports")
    heading: Strings.t("confirm.default.ports")
    subtitle: ""
    confirmText: Strings.t("apply")
    cancelText: Strings.t("cancel")
    bodyScrollable: false
    footerDividerVisible: false
    transientParent: window

    onConfirmRequested: {
        appSettingsWindow.webPortField.text = "80"
        appSettingsWindow.databasePortField.text = "3306"
        appSettingsWindow.redisPortField.text = "6379"
        appSettingsWindow.memcachedPortField.text = "11211"
        appSettingsWindow.mailpitSmtpPortField.text = "1025"
        appSettingsWindow.mailpitHttpPortField.text = "8025"
        window.defaultPortsConfirmOpen = false
    }

    onCancelRequested: {
        window.defaultPortsConfirmOpen = false
    }

    onVisibleChanged: {
        if (!visible) {
            window.defaultPortsConfirmOpen = false
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 14

        Text {
            Layout.fillWidth: true
            text: Strings.t("this.will.fill.the.form.with.default.ports.without.saving.yet.apache.nginx.80.database.3306.redis.6379.memcached.11211.mailpit.smtp.1025.mailpit.web.8025")
            color: Theme.text
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
    }
}
