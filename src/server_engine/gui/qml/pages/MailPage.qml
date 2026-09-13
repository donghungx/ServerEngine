import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../dialogs" as Dialogs
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    required property var dashboardBridge
    signal openBottomMailRequested()
    border.width: 0
    color: "transparent"

    readonly property bool mailpitRunning: String(dashboardBridge.mailpitServiceState || "").toLowerCase() === "running"
    property bool runtimePopupOpen: false
    property bool mailActionClickLock: false
    property string runtimePopupSection: "general"
    property var runtimePopupSections: [
        { id: "general", label: Strings.t("general") },
        { id: "service", label: Strings.t("service") },
        { id: "port", label: Strings.t("port") },
        { id: "switch.version", label: Strings.t("switch.version") },
        { id: "logs", label: Strings.t("logs") }
    ]
    property string smtpPortDraft: "1025"
    property string webPortDraft: "8025"
    property string mailpitGeneralMaxMessagesDraft: "500"
    property string mailpitGeneralMaxAgeDraft: ""
    property string mailpitGeneralCompressionDraft: "1"
    property string mailpitGeneralLabelDraft: ""
    property string mailpitGeneralTenantIdDraft: ""
    property string mailpitGeneralLogFileDraft: ""
    property string mailpitGeneralLoggingModeDraft: "default"
    property bool mailpitGeneralPersistentStorageDraft: false
    property bool mailpitGeneralUseMessageDatesDraft: false
    property bool mailpitGeneralIgnoreDuplicateIdsDraft: false

    function refreshMailpitDraft() {
        var settings = dashboardBridge.mailpitGeneralConfigSettings || {}
        smtpPortDraft = String(dashboardBridge.mailpitSmtpPort || "1025")
        webPortDraft = String(dashboardBridge.mailpitHttpPort || "8025")
        mailpitGeneralMaxMessagesDraft = String(settings.max_messages !== undefined && settings.max_messages !== null ? settings.max_messages : 500)
        mailpitGeneralMaxAgeDraft = String(settings.max_age || "")
        mailpitGeneralCompressionDraft = String(settings.compression !== undefined ? settings.compression : "1")
        mailpitGeneralLabelDraft = String(settings.label || "")
        mailpitGeneralTenantIdDraft = String(settings.tenant_id || "")
        mailpitGeneralLogFileDraft = String(settings.log_file || "")
        mailpitGeneralLoggingModeDraft = String(settings.logging_mode || "default")
        mailpitGeneralPersistentStorageDraft = Boolean(settings.persistent_storage)
        mailpitGeneralUseMessageDatesDraft = Boolean(settings.use_message_dates)
        mailpitGeneralIgnoreDuplicateIdsDraft = Boolean(settings.ignore_duplicate_ids)
    }

    function runtimeSectionDescription(sectionLabel) {
        switch (sectionLabel) {
        case "general":
            return "Core Mailpit settings for storage, retention, identity, logging, and ports."
        case "switch.version":
            return Strings.t("choose.which.packaged.mailpit.runtime.should.be.active")
        case "port":
            return "Mailpit SMTP and web port settings, with restart-on-save behavior."
        case "logs":
            return Strings.t("read.the.latest.mailpit.runtime.log.output")
        default:
            return Strings.t("start.stop.restart.and.verify.mailpit.runtime.state")
        }
    }

    function runtimeSectionIcon(sectionLabel) {
        switch (sectionLabel) {
        case "general":
            return "settings"
        case "service":
            return "power-accent"
        case "port":
            return "ethernet-port"
        case "switch.version":
            return "git-compare-arrows"
        case "logs":
            return "file-text"
        default:
            return "settings"
        }
    }

    function syncMailpitMailboxEvents() {
        if (!dashboardBridge) {
            return
        }
        if (visible) {
            if (dashboardBridge.startMailpitMailboxEvents) {
                dashboardBridge.startMailpitMailboxEvents()
            }
        } else if (dashboardBridge.stopMailpitMailboxEvents) {
            dashboardBridge.stopMailpitMailboxEvents()
        }
    }

    Component.onCompleted: {
        refreshMailpitDraft()
        syncMailpitMailboxEvents()
    }
    onVisibleChanged: syncMailpitMailboxEvents()

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 64
        anchors.rightMargin: 16
        spacing: 16

        Item {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            implicitHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                spacing: 14

                Label {
                    text: Strings.t("mail.server")
                    color: Theme.text
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }

                Label {
                    text: Strings.t("local.smtp.catcher.powered.by.mailpit.send.emails.to.smtp.127.0.0.1") + dashboardBridge.mailpitSmtpPort + " and view them at " + dashboardBridge.mailpitWebUrl + "."
                    color: Theme.muted
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 120
                    radius: Theme.radius
                    color: Theme.surface
                    border.color: Theme.border
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6

                            Text {
                                text: Strings.t("mailpit")
                                color: Theme.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            RowLayout {
                                spacing: 8

                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: root.mailpitRunning ? "#4aa94b" : "#bb4d4d"
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: Strings.t("status") + ": " + dashboardBridge.mailpitServiceState
                                    color: Theme.muted
                                    font.pixelSize: 13
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            Text {
                                text: Strings.t("smtp") + dashboardBridge.mailpitSmtpPort + " • Web " + dashboardBridge.mailpitHttpPort
                                color: Theme.muted
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                Row {
                    spacing: 10

                    Timer {
                        id: mailActionClickLockTimer
                        interval: 700
                        repeat: false
                        onTriggered: root.mailActionClickLock = false
                    }

                    Components.AppButton {
                        text: dashboardBridge.mailpitActionBusy
                            ? (root.mailpitRunning ? "Stopping..." : "Starting...")
                            : (root.mailpitRunning ? "Stop" : "Start")
                        iconSource: "icons/lucide/power-accent.svg"
                        highlighted: !root.mailpitRunning
                        enabled: !dashboardBridge.mailpitActionBusy
                        textColor: highlighted ? "white" : "#bb4d4d"
                        onClicked: {
                            if (root.mailpitRunning) {
                                dashboardBridge.stopMailpitRuntime()
                            } else {
                                dashboardBridge.startMailpitRuntime()
                            }
                        }
                    }

                    Components.AppButton {
                        text: Strings.t("restart")
                        iconSource: "icons/lucide/rotate-cw.svg"
                        enabled: !dashboardBridge.mailpitActionBusy
                        onClicked: dashboardBridge.restartMailpitRuntime()
                    }

                    Components.AppButton {
                        text: "Mail Box"
                        iconSource: "icons/lucide/inbox.svg"
                        enabled: root.mailpitRunning && !dashboardBridge.mailpitActionBusy
                        opacity: enabled ? 1.0 : 0.55
                        onClicked: root.openBottomMailRequested()
                    }

                    Components.AppButton {
                        text: "WebMail"
                        iconSource: "icons/lucide/external-link.svg"
                        enabled: root.mailpitRunning
                            && !dashboardBridge.mailpitActionBusy
                            && !root.mailActionClickLock
                        opacity: enabled ? 1.0 : 0.55
                        onClicked: {
                            root.mailActionClickLock = true
                            mailActionClickLockTimer.restart()
                            dashboardBridge.openMailpit()
                        }
                    }

                    Components.AppButton {
                        text: "Send a Test Email"
                        iconSource: "icons/lucide/mail.svg"
                        enabled: root.mailpitRunning
                            && !dashboardBridge.mailpitActionBusy
                            && !root.mailActionClickLock
                        opacity: enabled ? 1.0 : 0.55
                        onClicked: {
                            root.mailActionClickLock = true
                            mailActionClickLockTimer.restart()
                            dashboardBridge.sendMailpitTestEmail()
                        }
                    }

                    Components.AppButton {
                        text: "Settings"
                        iconSource: "icons/lucide/settings.svg"
                        onClicked: {
                            root.refreshMailpitDraft()
                            root.runtimePopupSection = "general"
                            root.runtimePopupOpen = true
                        }
                    }

                }

                Text {
                    text: dashboardBridge.mailpitRuntimeMessage
                    color: dashboardBridge.mailpitRuntimeError ? "#bb4d4d" : "#4aa94b"
                    font.pixelSize: 13
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    visible: text.length > 0
                }
            }
        }
    }

    Dialogs.MailpitRuntimeDialog {
        id: mailpitRuntimeDialog
        pageRoot: root
        dashboardBridge: root.dashboardBridge
    }
}
