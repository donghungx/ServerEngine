import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Qt.labs.platform as Native
import "../components" as Components
import "../dialogs" as Dialogs
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    required property var dashboardBridge
    border.width: 0
    color: "transparent"
    readonly property bool redisRunning: String(dashboardBridge.activeRedisServiceState || "").toLowerCase() === "running"
    signal databaseCliRequested()
    property bool logsVisible: false
    property bool runtimePopupOpen: false
    property bool passwordPopupOpen: false
    property string passwordFeedback: ""
    property bool passwordFeedbackError: false
    property string redisGeneralPortDraft: "6379"
    property string redisGeneralBindAddressDraft: "127.0.0.1"
    property bool redisGeneralProtectedModeDraft: true
    property bool redisGeneralAppendOnlyDraft: false
    property string redisGeneralPasswordDraft: ""
    property string redisGeneralLogLevelDraft: "notice"
    property string redisGeneralDbFilenameDraft: "dump.rdb"
    property string redisConfigDraft: ""
    property string redisConfigFeedback: ""
    property string redisPortDraft: "6379"
    property string redisPortLoaded: "6379"
    property string runtimePopupSection: "general"
    property var runtimePopupSections: [
        { id: "general" },
        { id: "service" },
        { id: "switch.version" },
        { id: "configuration" },
        { id: "port" },
        { id: "logs" }
    ]

    function folderUrl(path) {
        return "file://" + encodeURI(path)
    }

    function refreshRedisConfigDraft() {
        root.refreshRedisGeneralDraft()
        root.redisConfigDraft = dashboardBridge.activeRedisConfigContent
        root.redisConfigFeedback = ""
        root.redisPortDraft = String(dashboardBridge.activeRedisPort || "6379")
        root.redisPortLoaded = root.redisPortDraft
    }

    function refreshRedisGeneralDraft() {
        var settings = dashboardBridge.redisGeneralConfigSettings || {}
        root.redisGeneralPortDraft = String(dashboardBridge.activeRedisPort || "6379")
        root.redisGeneralBindAddressDraft = String(settings.bind_address || "127.0.0.1")
        root.redisGeneralProtectedModeDraft = Boolean(settings.protected_mode)
        root.redisGeneralAppendOnlyDraft = Boolean(settings.appendonly)
        root.redisGeneralPasswordDraft = String(dashboardBridge.redisPassword || "")
        root.redisGeneralLogLevelDraft = String(settings.log_level || "notice")
        root.redisGeneralDbFilenameDraft = String(settings.db_filename || "dump.rdb")
    }

    function runtimeSectionDescription(sectionId) {
        switch (sectionId) {
        case "general":
            return "General Redis connection, persistence, security, and runtime defaults."
        case "switch.version":
            return "Choose which packaged Redis runtime should be active."
        case "configuration":
            return "Redis runtime config path and generated config file location."
        case "port":
            return "Configure the Redis listen port for the active runtime."
        case "logs":
            return "Read the latest Redis runtime log output."
        default:
            return "Start, stop, and restart the active Redis runtime."
        }
    }

    function redisRuntimeSectionSource(sectionId) {
        switch (sectionId) {
        case "general":
            return "redis_runtime_sections/GeneralSection.qml"
        case "service":
            return "redis_runtime_sections/ServiceSection.qml"
        case "switch.version":
            return "redis_runtime_sections/SwitchVersionSection.qml"
        case "configuration":
            return "redis_runtime_sections/ConfigFileSection.qml"
        case "port":
            return "redis_runtime_sections/PortSection.qml"
        case "logs":
            return "redis_runtime_sections/LogsSection.qml"
        default:
            return "redis_runtime_sections/PlaceholderSection.qml"
        }
    }

    function runtimeSectionIcon(sectionId) {
        switch (sectionId) {
        case "general":
            return "settings"
        case "service":
            return "power-accent"
        case "switch.version":
            return "git-compare-arrows"
        case "configuration":
            return "file-text"
        case "port":
            return "ethernet-port"
        case "logs":
            return "file-text"
        default:
            return "settings"
        }
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 64
        anchors.rightMargin: 16
        spacing: 14

        Item {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            implicitHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                spacing: 14

                Text {
                    text: Strings.t("redis")
                    color: Theme.text
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }

                Text {
                    text: Strings.t("manage.redis.runtime.behavior.version.selection.and.runtime.controls")
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
                                text: Strings.t("redis")
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
                                    color: root.redisRunning ? "#4aa94b" : "#bb4d4d"
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: Strings.t("status") + ": " + dashboardBridge.activeRedisServiceState
                                    color: Theme.muted
                                    font.pixelSize: 13
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            Text {
                                text: Strings.t("runtime") + " " + dashboardBridge.activeRedisRuntimeLabel + " • Port " + dashboardBridge.activeRedisPort + " • Password " + (dashboardBridge.redisPassword.length > 0 ? "Configured" : "Not set")
                                color: Theme.muted
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                Row {
                    spacing: 10

                    Components.AppButton {
                        visible: !root.redisRunning

                        text: dashboardBridge.redisActionBusy
                            ? "Starting..."
                            : "Start"
                        iconSource: "icons/lucide/power-accent.svg"

                        highlighted: true
                        enabled: !dashboardBridge.redisActionBusy

                        textColor: "white"

                        onClicked: dashboardBridge.startRedisRuntime()
                    }

                    Components.AppButton {
                        visible: root.redisRunning

                        text: dashboardBridge.redisActionBusy
                            ? "Stopping..."
                            : "Stop"
                        iconSource: "icons/lucide/power-accent.svg"

                        enabled: !dashboardBridge.redisActionBusy

                        textColor: Theme.danger

                        onClicked: dashboardBridge.stopRedisRuntime()
                    }

                    Components.AppButton {
                        text: Strings.t("restart")
                        iconSource: "icons/lucide/rotate-cw.svg"
                        enabled: !dashboardBridge.redisActionBusy

                        onClicked: dashboardBridge.restartRedisRuntime()
                    }

                    Components.AppButton {
                        text: Strings.t("change.password")
                        iconSource: "icons/lucide/shield.svg"

                        onClicked: root.passwordPopupOpen = true
                    }

                    Components.AppButton {
                        text: Strings.t("cli")
                        iconSource: "icons/lucide/terminal.svg"
                        enabled: root.redisRunning
                        onClicked: root.databaseCliRequested()
                    }

                    Components.AppButton {
                        text: Strings.t("settings")
                        iconSource: "icons/lucide/settings.svg"

                        onClicked: {
                            root.runtimePopupOpen = true
                            root.runtimePopupSection = "general"
                        }
                    }

                }

                Text {
                    text: dashboardBridge.redisRuntimeMessage.length > 0
                        ? dashboardBridge.redisRuntimeMessage
                        : "Use Start, Stop, and Restart to control the active Redis runtime."
                    color: dashboardBridge.redisRuntimeError ? "#bb4d4d" : Theme.accentStrong
                    font.pixelSize: 13
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: root.logsVisible
                    Layout.preferredHeight: root.logsVisible ? -1 : 0
                    radius: Theme.radius
                    color: "transparent"
                    border.color: Theme.border
                    border.width: 1
                    visible: root.logsVisible

                    Components.AppScrollEditor {
                        id: redisLogText
                        anchors.fill: parent
                        anchors.margins: 12
                        text: dashboardBridge.redisRuntimeLog.length > 0
                            ? dashboardBridge.redisRuntimeLog
                            : "No Redis runtime log yet."
                        textColor: Theme.text
                        fontPixelSize: 12
                        fontFamily: "Menlo"
                        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                        readOnly: true
                        selectByMouse: true
                    }
                }


    }

    Native.Menu {
        id: redisInlineLogMenu
        Native.MenuItem {
            text: Strings.t("copy")
            enabled: redisLogText.selectedText.length > 0
            onTriggered: redisLogText.copy()
        }
        Native.MenuSeparator {}
        Native.MenuItem {
            text: Strings.t("select.all")
            enabled: redisLogText.length > 0
            onTriggered: redisLogText.selectAll()
        }
    }

    Dialogs.RedisRuntimeDialog {
        pageRoot: root
        dashboardBridge: root.dashboardBridge
    }

    Dialogs.RedisPasswordDialog {
        pageRoot: root
        dashboardBridge: root.dashboardBridge
    }
}
