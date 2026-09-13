import QtQuick
import "../../theme"

Rectangle {
    id: bottomLogsPanel

    signal hideRequested()

    required property var dashboardBridge
    required property bool bottomLogsOpen
    required property var statusBarItem
    required property var appWindow
    property bool dockMode: false
    readonly property int minimumExpandedHeight: 80
    property bool logsResizing: false

    anchors {
        left: parent.left
        right: parent.right
        bottom: dockMode ? parent.bottom : statusBarItem.top
    }
    height: dockMode
        ? (parent ? parent.height : 0)
        : (bottomLogsOpen ? Math.min(sharedLogsHeight(), logsMaxExpandedHeight()) : 0)
    color: Theme.surfaceAlt
    clip: true
    visible: dockMode ? true : height > 0

    Behavior on height {
        enabled: !bottomLogsPanel.logsResizing
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    onBottomLogsOpenChanged: {
        if (bottomLogsOpen) {
            logsPage.requestRefreshLogs()
        }
    }

    Item {
        id: logsResizeTopHandle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 6
        z: 100
        visible: !bottomLogsPanel.dockMode

        MouseArea {
            id: logsResizeTopMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            property real dragStartSceneY: 0
            property int dragStartHeight: 0

            onPressed: function(mouse) {
                bottomLogsPanel.logsResizing = true
                dragStartSceneY = logsResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                dragStartHeight = sharedLogsHeight()
                mouse.accepted = true
            }

            onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) {
                    return
                }
                var currentSceneY = logsResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                setSharedLogsHeight(dragStartHeight + (dragStartSceneY - currentSceneY))
            }

            onReleased: function(mouse) {
                bottomLogsPanel.logsResizing = false
                if (bottomLogsPanel.dashboardBridge && bottomLogsPanel.dashboardBridge.saveBottomTerminalPanelHeight) {
                    bottomLogsPanel.dashboardBridge.saveBottomTerminalPanelHeight(sharedLogsHeight())
                }
                mouse.accepted = true
            }

            onCanceled: {
                bottomLogsPanel.logsResizing = false
            }
        }
    }

    LogPanel {
        id: logsPage
        anchors.fill: parent
        dashboardBridge: bottomLogsPanel.dashboardBridge
        panelOpen: bottomLogsPanel.bottomLogsOpen
        onHideRequested: bottomLogsPanel.hideRequested()
    }

    function sharedLogsHeight() {
        if (bottomLogsPanel.appWindow && bottomLogsPanel.appWindow.bottomPanelHeight !== undefined) {
            return Math.max(minimumExpandedHeight, Number(bottomLogsPanel.appWindow.bottomPanelHeight || minimumExpandedHeight))
        }
        return minimumExpandedHeight
    }

    function logsMaxExpandedHeight() {
        return Math.max(
            minimumExpandedHeight,
            Math.floor(((parent && parent.height) ? parent.height : 0) * 2 / 3)
        )
    }

    function clampLogsHeight(nextHeight) {
        return Math.max(
            minimumExpandedHeight,
            Math.min(logsMaxExpandedHeight(), Math.floor(nextHeight))
        )
    }

    function setSharedLogsHeight(nextHeight) {
        var clamped = clampLogsHeight(nextHeight)
        if (bottomLogsPanel.appWindow && bottomLogsPanel.appWindow.bottomPanelHeight !== undefined) {
            bottomLogsPanel.appWindow.bottomPanelHeight = clamped
        }
    }
}
