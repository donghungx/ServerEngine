import QtQuick
import QtQuick.Controls
import "../theme"
import "." as Shell
import "./mail" as Mail
import "./logs" as Logs
import "./redis" as Redis

Rectangle {
    id: root

    signal closeAllRequested()

    required property var dashboardBridge
    required property var terminalBackend
    required property var statusBarItem
    required property var appWindow
    required property bool bottomTerminalOpen
    required property bool bottomMailOpen
    required property bool bottomLogsOpen
    required property bool bottomRedisInspectorOpen

    readonly property int minimumExpandedHeight: 80
    property bool resizing: false

    anchors {
        left: parent.left
        right: parent.right
        bottom: statusBarItem.top
    }

    height: activePanel.length > 0 ? Math.min(sharedHeight(), activePanelMaxHeight()) : 0
    color: Theme.surfaceAlt
    clip: true
    visible: height > 0

    Behavior on height {
        enabled: !root.resizing
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    readonly property string activePanel: bottomMailOpen
        ? "mail"
        : (bottomTerminalOpen
            ? "terminal"
            : (bottomLogsOpen
                ? "logs"
                : (bottomRedisInspectorOpen ? "redis" : "")))

    function panelMinHeight(panelId) {
        switch (String(panelId || "")) {
        case "redis":
            return 160
        case "mail":
        case "terminal":
        case "logs":
        default:
            return minimumExpandedHeight
        }
    }

    function activePanelMinHeight() {
        return panelMinHeight(activePanel)
    }

    function activePanelMaxHeight() {
        return Math.max(
            activePanelMinHeight(),
            Math.floor(((parent && parent.height) ? parent.height : 0) * 2 / 3)
        )
    }

    function clampHeight(nextHeight) {
        return Math.max(activePanelMinHeight(), Math.min(activePanelMaxHeight(), Math.floor(nextHeight)))
    }

    function sharedHeight() {
        if (root.appWindow && root.appWindow.bottomPanelHeight !== undefined) {
            return Math.max(activePanelMinHeight(), Number(root.appWindow.bottomPanelHeight || activePanelMinHeight()))
        }
        return activePanelMinHeight()
    }

    function setSharedHeight(nextHeight) {
        var clamped = clampHeight(nextHeight)
        if (root.appWindow && root.appWindow.bottomPanelHeight !== undefined) {
            root.appWindow.bottomPanelHeight = clamped
        }
    }

    Item {
        id: resizeHandle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 3
        z: 100

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.border
            z: 99
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            property real dragStartSceneY: 0
            property int dragStartHeight: 0

            onPressed: function(mouse) {
                root.resizing = true
                dragStartSceneY = resizeHandle.mapToItem(null, mouse.x, mouse.y).y
                dragStartHeight = sharedHeight()
                mouse.accepted = true
            }

            onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) {
                    return
                }
                var currentSceneY = resizeHandle.mapToItem(null, mouse.x, mouse.y).y
                setSharedHeight(dragStartHeight + (dragStartSceneY - currentSceneY))
            }

            onReleased: function(mouse) {
                root.resizing = false
                if (root.appWindow && root.appWindow.bottomPanelHeight !== undefined) {
                    root.appWindow.bottomPanelHeight = sharedHeight()
                }
                mouse.accepted = true
            }

            onCanceled: root.resizing = false
        }
    }

    Item {
        id: contentHost
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: resizeHandle.bottom
        anchors.bottom: parent.bottom

        Mail.BottomMailPanel {
            id: mailPanel
            anchors.fill: parent
            dashboardBridge: root.dashboardBridge
            bottomMailOpen: root.bottomMailOpen
            statusBarItem: root.statusBarItem
            appWindow: root.appWindow
            dockMode: true
            visible: root.activePanel === "mail"
            onHideRequested: root.closeAllRequested()
        }

        // Terminal, logs, and Redis panels are kept mounted here as siblings.
        // Visibility is controlled by activePanel so switching does not destroy them.
        Shell.BottomTerminalPanel {
            id: terminalPanel
            anchors.fill: parent
            terminalBackend: root.terminalBackend
            bottomTerminalOpen: root.bottomTerminalOpen
            statusBarItem: root.statusBarItem
            appWindow: root.appWindow
            dashboardBridge: root.dashboardBridge
            dockMode: true
            visible: root.activePanel === "terminal"
            onHideRequested: root.closeAllRequested()
        }

        Logs.BottomLogsPanel {
            id: logsPanel
            anchors.fill: parent
            dashboardBridge: root.dashboardBridge
            bottomLogsOpen: root.bottomLogsOpen
            statusBarItem: root.statusBarItem
            appWindow: root.appWindow
            dockMode: true
            visible: root.activePanel === "logs"
            onHideRequested: root.closeAllRequested()
        }

        Redis.BottomRedisInspectorPanel {
            id: redisInspectorPanel
            anchors.fill: parent
            dashboardBridge: root.dashboardBridge
            bottomRedisInspectorOpen: root.bottomRedisInspectorOpen
            statusBarItem: root.statusBarItem
            appWindow: root.appWindow
            dockMode: true
            visible: root.activePanel === "redis"
            onHideRequested: root.closeAllRequested()
        }
    }

    function requestRefreshMailbox() {
        if (mailPanel && mailPanel.requestRefreshMailbox) {
            mailPanel.requestRefreshMailbox()
        }
    }

    function requestRefreshInspector() {
        if (redisInspectorPanel && redisInspectorPanel.requestRefreshInspector) {
            redisInspectorPanel.requestRefreshInspector()
        }
    }

    function ensureDefaultSession() {
        if (terminalPanel && terminalPanel.ensureDefaultSession) {
            terminalPanel.ensureDefaultSession()
        }
    }

    function beginExplicitSessionOpen() {
        if (terminalPanel && terminalPanel.beginExplicitSessionOpen) {
            terminalPanel.beginExplicitSessionOpen()
        }
    }

    function finishExplicitSessionOpen() {
        if (terminalPanel && terminalPanel.finishExplicitSessionOpen) {
            terminalPanel.finishExplicitSessionOpen()
        }
    }

    function openDefaultSession() {
        if (terminalPanel && terminalPanel.openDefaultSession) {
            terminalPanel.openDefaultSession()
        }
    }

    function openActiveDatabaseSession() {
        if (terminalPanel && terminalPanel.openActiveDatabaseSession) {
            terminalPanel.openActiveDatabaseSession()
        }
    }

    function openActiveMongodbSession() {
        if (terminalPanel && terminalPanel.openActiveMongodbSession) {
            terminalPanel.openActiveMongodbSession()
        }
    }

    function openActivePostgresqlSession() {
        if (terminalPanel && terminalPanel.openActivePostgresqlSession) {
            terminalPanel.openActivePostgresqlSession()
        }
    }

    function openActiveRedisSession() {
        if (terminalPanel && terminalPanel.openActiveRedisSession) {
            terminalPanel.openActiveRedisSession()
        }
    }

    function openWebsiteSession(siteId) {
        if (terminalPanel && terminalPanel.openWebsiteSession) {
            terminalPanel.openWebsiteSession(siteId)
        }
    }

    function openNodeProjectSession(nodeProjectId) {
        if (terminalPanel && terminalPanel.openNodeProjectSession) {
            terminalPanel.openNodeProjectSession(nodeProjectId)
        }
    }

}
