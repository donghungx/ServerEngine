import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../components" as Components
import "../theme"
import "../i18n"

Rectangle {
    id: statusBar
    signal toggleBottomTerminalRequested()
    signal toggleBottomMailRequested()
    signal toggleBottomLogsRequested()
    signal toggleBottomRedisInspectorRequested()

    required property var dashboardBridge
    required property bool globalStatusError
    required property string globalStatusDisplayMessage
    required property bool statusCursorVisible
    required property bool bottomTerminalOpen
    required property bool bottomMailOpen
    required property bool bottomLogsOpen
    required property bool bottomRedisInspectorOpen
    required property var statusTypeTimer

    height: 32
    anchors {
        left: parent.left
        right: parent.right
        bottom: parent.bottom
    }

    color: Theme.surfaceAlt
    Behavior on color {
        ColorAnimation { duration: 140 }
    }
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        height: 1
        color: Theme.border
    }

    function currentJobCardState() {
        if (dashboardBridge.databaseBackupBusy) {
            return {
                busy: true,
                title: String(dashboardBridge.databaseBackupJobTitle || dashboardBridge.databaseBackupProgressLabel || ""),
                progress: Number(dashboardBridge.databaseBackupProgress || 0),
                cancelable: true
            }
        }
        if (dashboardBridge.databaseImportBusy) {
            return {
                busy: true,
                title: String(dashboardBridge.databaseImportJobTitle || dashboardBridge.databaseImportProgressLabel || "Importing..."),
                progress: Number(dashboardBridge.databaseImportProgress || 0),
                cancelable: false
            }
        }
        if (dashboardBridge.postgresqlBackupBusy) {
            return {
                busy: true,
                title: String(dashboardBridge.postgresqlBackupProgressLabel || "Working..."),
                progress: Number(dashboardBridge.postgresqlBackupProgress || 0),
                cancelable: false
            }
        }
        if (dashboardBridge.postgresqlImportBusy) {
            return {
                busy: true,
                title: String(dashboardBridge.postgresqlImportProgressLabel || "Working..."),
                progress: Number(dashboardBridge.postgresqlImportProgress || 0),
                cancelable: false
            }
        }
        if (dashboardBridge.mongodbBackupBusy) {
            return {
                busy: true,
                title: String(dashboardBridge.mongodbBackupProgressLabel || "Working..."),
                progress: Number(dashboardBridge.mongodbBackupProgress || 0),
                cancelable: false
            }
        }
        if (dashboardBridge.mongodbImportBusy) {
            return {
                busy: true,
                title: String(dashboardBridge.mongodbImportProgressLabel || "Working..."),
                progress: Number(dashboardBridge.mongodbImportProgress || 0),
                cancelable: false
            }
        }
        return { busy: false, title: "", progress: 0, cancelable: false }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                id: statusTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Strings.t("status") + ":"
                color: globalStatusError ? "#d66a6a" : Theme.text
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Item {
                id: statusMessageViewport
                anchors.left: statusTitle.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 16
                clip: true

                property real marqueeOffset: 0
                property bool needsMarquee: statusMessageText.implicitWidth > width + 8

                onWidthChanged: marqueeOffset = 0
                onNeedsMarqueeChanged: {
                    if (!needsMarquee) {
                        marqueeOffset = 0
                    }
                }

                SequentialAnimation on marqueeOffset {
                    running: statusMessageViewport.needsMarquee && !statusTypeTimer.running
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 0; duration: 1000 }
                    NumberAnimation {
                        from: 0
                        to: Math.max(0, statusMessageText.implicitWidth - statusMessageViewport.width + 12)
                        duration: 9000
                        easing.type: Easing.Linear
                    }
                    NumberAnimation { from: 0; to: 0; duration: 700 }
                }

                Text {
                    id: statusMessageText
                    x: -statusMessageViewport.marqueeOffset
                    anchors.verticalCenter: parent.verticalCenter
                    text: globalStatusDisplayMessage
                        + (statusTypeTimer.running && statusCursorVisible ? "_" : "")
                    color: globalStatusError ? "#d66a6a" : Theme.muted
                    font.pixelSize: 11
                    wrapMode: Text.NoWrap
                }
            }
        }

        Components.JobProgressCard {
            id: databaseJobCard
            Layout.alignment: Qt.AlignVCenter
            busy: currentJobCardState().busy
            title: currentJobCardState().title
            progress: currentJobCardState().progress
            cancelable: currentJobCardState().cancelable
            onCancelRequested: dashboardBridge.cancelDatabaseBackupJob()
        }

        Components.StatusTextButton {
            label: "Mail"
            iconSource: "../icons/lucide/mail.svg"
            active: bottomMailOpen
            enabled: bottomMailOpen || (String(dashboardBridge.mailpitServiceState || "").toLowerCase() === "running" && !dashboardBridge.mailpitActionBusy)
            tooltip: bottomMailOpen
                ? "Close mail"
                : (String(dashboardBridge.mailpitServiceState || "").toLowerCase() === "running"
                    ? "Open mailbox"
                    : "Need Mailpit to start to read mail.")
            onClicked: statusBar.toggleBottomMailRequested()
        }

        Components.StatusTextButton {
            label: "Redis Inspector"
            iconSource: "../icons/lucide/search.svg"
            active: bottomRedisInspectorOpen
            enabled: bottomRedisInspectorOpen || (String(dashboardBridge.activeRedisServiceState || "").toLowerCase() === "running" && !dashboardBridge.redisActionBusy)
            tooltip: bottomRedisInspectorOpen
                ? "Close Redis Inspector"
                : (String(dashboardBridge.activeRedisServiceState || "").toLowerCase() === "running"
                    ? "Open Redis Inspector"
                    : "Need Redis to start to inspect keys.")
            onClicked: statusBar.toggleBottomRedisInspectorRequested()
        }

        Components.StatusTextButton {
            label: Strings.t("cli")
            iconSource: "../icons/lucide/terminal.svg"
            active: bottomTerminalOpen
            onClicked: statusBar.toggleBottomTerminalRequested()
        }

        Components.StatusTextButton {
            label: Strings.t("logs")
            iconSource: "../icons/lucide/file-text.svg"
            active: bottomLogsOpen
            onClicked: statusBar.toggleBottomLogsRequested()
        }
    }
}
