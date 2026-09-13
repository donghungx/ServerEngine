import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Qt.labs.platform as Native
import "../components" as Components
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    required property var dashboardBridge
    border.width: 0
    color: "transparent"
    readonly property bool memcachedMode: true
    readonly property bool cacheRunning: String(dashboardBridge.activeMemcachedServiceState || "").toLowerCase() === "running"
    property bool logsVisible: false
    property bool runtimePopupOpen: false
    property string memcachedConfigDraft: ""
    property string memcachedConfigFeedback: ""
    property string memcachedHostDraft: "127.0.0.1"
    property string memcachedPortDraft: "11211"
    property string memcachedPortLoaded: "11211"
    property bool pendingMemcachedRestartConfirm: false
    property bool memcachedRestartConfirmOpen: false
    property string runtimePopupSection: "service"
    property var runtimePopupSections: [
        { id: "service", label: Strings.t("service") },
        { id: "switch.version", label: Strings.t("switch.version") },
        { id: "configuration", label: Strings.t("configuration") },
        { id: "port", label: Strings.t("port") },
        { id: "logs", label: Strings.t("logs") }
    ]

    function folderUrl(path) {
        return "file://" + encodeURI(path)
    }

    function refreshMemcachedConfigDraft() {
        root.memcachedConfigDraft = dashboardBridge.activeMemcachedConfigContent
        root.memcachedConfigFeedback = ""
        var settings = dashboardBridge.memcachedConfigSettings()
        if (settings) {
            root.memcachedHostDraft = String(settings.host || "127.0.0.1")
            root.memcachedPortDraft = String(settings.port || "11211")
            root.memcachedPortLoaded = root.memcachedPortDraft
        }
        root.pendingMemcachedRestartConfirm = false
    }

    function runtimeSectionDescription(sectionLabel) {
        switch (sectionLabel) {
        case "switch.version":
            return Strings.t("choose.which.packaged.memcached.runtime.should.be.active")
        case "configuration":
            return Strings.t("memcached.runtime.config.path.and.generated.config.file.location")
        case "port":
            return Strings.t("configure.the.memcached.listen.port.for.the.active.runtime")
        case "logs":
            return Strings.t("read.the.latest.memcached.runtime.log.output")
        default:
            return Strings.t("start.stop.and.restart.the.active.memcached.runtime")
        }
    }

    function memcachedRuntimeSectionSource(sectionLabel) {
        switch (sectionLabel) {
        case "service":
            return "memcached_runtime_sections/ServiceSection.qml"
        case "switch.version":
            return "memcached_runtime_sections/SwitchVersionSection.qml"
        case "configuration":
            return "memcached_runtime_sections/ConfigFileSection.qml"
        case "port":
            return "memcached_runtime_sections/PortSection.qml"
        case "logs":
            return "memcached_runtime_sections/LogsSection.qml"
        default:
            return "memcached_runtime_sections/PlaceholderSection.qml"
        }
    }

    function runtimeSectionIcon(sectionLabel) {
        switch (sectionLabel) {
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
                    text: Strings.t("memcached")
                    color: Theme.text
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }

                Text {
                    text: Strings.t("manage.memcached.runtime.controls.and.version.selection.here")
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
                                text: Strings.t("memcached")
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
                                    color: root.cacheRunning ? "#4aa94b" : "#bb4d4d"
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: Strings.t("status") + ": " + dashboardBridge.activeMemcachedServiceState
                                    color: Theme.muted
                                    font.pixelSize: 13
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            Text {
                                text: Strings.t("runtime") + " " + dashboardBridge.activeMemcachedRuntimeLabel + " • Port " + dashboardBridge.activeMemcachedPort
                                color: Theme.muted
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                Row {
                    spacing: 10
                    visible: root.memcachedMode

                    Components.AppButton {
                        visible: !root.cacheRunning

                        text: dashboardBridge.memcachedActionBusy
                            ? "Starting..."
                            : "Start"
                        iconSource: "icons/lucide/power-accent.svg"

                        highlighted: true
                        enabled: !dashboardBridge.memcachedActionBusy

                        textColor: "white"

                        onClicked: dashboardBridge.startMemcachedRuntime()
                    }

                    Components.AppButton {
                        visible: root.cacheRunning

                        text: dashboardBridge.memcachedActionBusy
                            ? "Stopping..."
                            : "Stop"
                        iconSource: "icons/lucide/power-accent.svg"

                        enabled: !dashboardBridge.memcachedActionBusy

                        textColor: "#bb4d4d"

                        onClicked: dashboardBridge.stopMemcachedRuntime()
                    }

                    Components.AppButton {
                        text: Strings.t("restart")
                        iconSource: "icons/lucide/rotate-cw.svg"
                        enabled: !dashboardBridge.memcachedActionBusy

                        onClicked: dashboardBridge.restartMemcachedRuntime()
                    }

                    Components.AppButton {
                        text: Strings.t("settings")
                        iconSource: "icons/lucide/settings.svg"

                        onClicked: {
                            root.runtimePopupOpen = true
                            root.runtimePopupSection = "service"
                        }
                    }

                }

                Text {
                    text: dashboardBridge.memcachedRuntimeMessage.length > 0
                        ? dashboardBridge.memcachedRuntimeMessage
                        : "Use Start, Stop, and Restart to control the active Memcached runtime."
                    color: dashboardBridge.memcachedRuntimeError ? "#bb4d4d" : Theme.accentStrong
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
                    color: "#101317"
                    border.color: "#1d242b"
                    border.width: 1
                    visible: root.logsVisible

                    Components.AppScrollEditor {
                        id: redisLogText
                        anchors.fill: parent
                        anchors.margins: 12
                        text: dashboardBridge.memcachedRuntimeLog.length > 0
                            ? dashboardBridge.memcachedRuntimeLog
                            : "No Memcached runtime log yet."
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
        id: memcachedInlineLogMenu
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

    Window {
        id: memcachedRuntimeWindow
        visible: root.runtimePopupOpen
        width: 720
        height: 480
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: dashboardBridge.activeMemcachedRuntimeLabel + " Runtime"
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root.Window.window
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (visible) {
                root.refreshMemcachedConfigDraft()
                Qt.callLater(function() {
                    dashboardBridge.refreshMemcachedRuntime()
                })
            } else {
                root.runtimePopupOpen = false
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    color: Theme.titleBar

                    MouseArea {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 24
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.ArrowCursor
                        onPressed: function(mouse) {
                            memcachedRuntimeWindow.startSystemMove()
                            mouse.accepted = true
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.border
                    }

                    Text {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 8
                        text: Strings.t(root.runtimePopupSection)
                        color: Theme.text
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Item {
                        anchors.fill: parent
                        anchors.topMargin: 28
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.bottomMargin: 6
                        clip: true

                        Row {
                            height: 58
                            spacing: 6

                            Repeater {
                                model: root.runtimePopupSections

                                delegate: Components.TopIconTab {
                                    id: runtimeTopTabItem
                                    required property int index
                                    property var navItem: root.runtimePopupSections[index]
                                    selected: root.runtimePopupSection === navItem.id
                                    label: runtimeTopTabItem.navItem.label
                                    iconSource: "../icons/lucide/" + root.runtimeSectionIcon(runtimeTopTabItem.navItem.id) + ".svg"
                                    onClicked: {
                                        root.runtimePopupSection = runtimeTopTabItem.navItem.id
                                        if (runtimeTopTabItem.navItem.id === "configuration"
                                                || runtimeTopTabItem.navItem.id === "port") {
                                            root.refreshMemcachedConfigDraft()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 20

                        Loader {
                            id: memcachedRuntimeSectionLoader
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            source: root.memcachedRuntimeSectionSource(root.runtimePopupSection)
                            onLoaded: {
                                if (item) {
                                    item.pageRoot = root
                                    item.dashboardBridge = dashboardBridge
                                    item.runtimeWindow = memcachedRuntimeWindow
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Window {
        id: memcachedRestartConfirmWindow
        visible: root.memcachedRestartConfirmOpen
        width: 480
        height: 120
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: Strings.t("restart.memcached")
        modality: Qt.ApplicationModal
        transientParent: memcachedRuntimeWindow
        flags: Qt.Window
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        x: memcachedRuntimeWindow.x + Math.round((memcachedRuntimeWindow.width - width) / 2)
        y: memcachedRuntimeWindow.y + Math.round((memcachedRuntimeWindow.height - height) / 2)

        onVisibleChanged: {
            if (!visible) {
                root.memcachedRestartConfirmOpen = false
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface

            MouseArea {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 24
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.ArrowCursor
                onPressed: function(mouse) {
                    memcachedRestartConfirmWindow.startSystemMove()
                    mouse.accepted = true
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Label {
                    Layout.fillWidth: true
                    text: Strings.t("port.changed.restart.memcached.now")
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    Components.AppButton {
                        text: Strings.t("later")
                        onClicked: root.memcachedRestartConfirmOpen = false
                    }

                    Components.AppButton {
                        text: Strings.t("restart")
                        highlighted: true
                        textColor: "white"
                        onClicked: {
                            root.memcachedRestartConfirmOpen = false
                            dashboardBridge.restartMemcachedRuntime()
                        }
                    }
                }
            }
        }
    }

}
