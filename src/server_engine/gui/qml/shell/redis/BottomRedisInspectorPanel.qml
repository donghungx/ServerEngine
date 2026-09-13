import QtQuick
import "../../theme"

Rectangle {
    id: bottomRedisInspectorPanel

    signal hideRequested()
    required property var dashboardBridge
    required property bool bottomRedisInspectorOpen
    required property var statusBarItem
    required property var appWindow
    property bool inspectorResizing: false
    property bool dockMode: false

    anchors {
        left: parent.left
        right: parent.right
        bottom: dockMode ? parent.bottom : statusBarItem.top
    }
    height: dockMode
        ? (parent ? parent.height : 0)
        : (bottomRedisInspectorOpen ? Math.min(sharedInspectorHeight(), inspectorMaxExpandedHeight()) : 0)
    clip: true
    visible: dockMode ? true : height > 0

    Behavior on height {
        enabled: !bottomRedisInspectorPanel.inspectorResizing
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    onBottomRedisInspectorOpenChanged: {
        if (bottomRedisInspectorOpen) {
            if (bottomRedisInspectorPanel.dashboardBridge && bottomRedisInspectorPanel.dashboardBridge.startRedisInspectorLiveUpdates) {
                bottomRedisInspectorPanel.dashboardBridge.startRedisInspectorLiveUpdates()
            }
            requestRefreshInspector()
        } else if (bottomRedisInspectorPanel.dashboardBridge && bottomRedisInspectorPanel.dashboardBridge.stopRedisInspectorLiveUpdates) {
            bottomRedisInspectorPanel.dashboardBridge.stopRedisInspectorLiveUpdates()
        }
    }

    Item {
        id: inspectorResizeTopHandle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 6
        z: 100
        visible: !bottomRedisInspectorPanel.dockMode

        MouseArea {
            id: inspectorResizeTopMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            property real dragStartSceneY: 0
            property int dragStartHeight: 0

            onPressed: function(mouse) {
                bottomRedisInspectorPanel.inspectorResizing = true
                dragStartSceneY = inspectorResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                dragStartHeight = sharedInspectorHeight()
                mouse.accepted = true
            }

            onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) {
                    return
                }
                var currentSceneY = inspectorResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                setSharedInspectorHeight(dragStartHeight + (dragStartSceneY - currentSceneY))
            }

            onReleased: function(mouse) {
                bottomRedisInspectorPanel.inspectorResizing = false
                if (bottomRedisInspectorPanel.dashboardBridge && bottomRedisInspectorPanel.dashboardBridge.saveBottomTerminalPanelHeight) {
                    bottomRedisInspectorPanel.dashboardBridge.saveBottomTerminalPanelHeight(sharedInspectorHeight())
                }
                mouse.accepted = true
            }

            onCanceled: {
                bottomRedisInspectorPanel.inspectorResizing = false
            }
        }
    }

    RedisInspectorPanel {
        id: inspectorPage
        anchors.fill: parent
        dashboardBridge: bottomRedisInspectorPanel.dashboardBridge
        panelOpen: bottomRedisInspectorPanel.bottomRedisInspectorOpen
        onHideRequested: bottomRedisInspectorPanel.hideRequested()
    }

    function sharedInspectorHeight() {
        if (bottomRedisInspectorPanel.appWindow && bottomRedisInspectorPanel.appWindow.bottomPanelHeight !== undefined) {
            return Math.max(minimumExpandedHeight, Number(bottomRedisInspectorPanel.appWindow.bottomPanelHeight || minimumExpandedHeight))
        }
        return minimumExpandedHeight
    }

    function inspectorMaxExpandedHeight() {
        return Math.max(
            minimumExpandedHeight,
            Math.floor(((parent && parent.height) ? parent.height : 0) * 2 / 3)
        )
    }

    function clampInspectorHeight(nextHeight) {
        return Math.max(
            minimumExpandedHeight,
            Math.min(inspectorMaxExpandedHeight(), Math.floor(nextHeight))
        )
    }

    function setSharedInspectorHeight(nextHeight) {
        var clamped = clampInspectorHeight(nextHeight)
        if (bottomRedisInspectorPanel.appWindow && bottomRedisInspectorPanel.appWindow.bottomPanelHeight !== undefined) {
            bottomRedisInspectorPanel.appWindow.bottomPanelHeight = clamped
        }
    }

    function requestRefreshInspector() {
        inspectorPage.requestRefreshInspector()
    }

    readonly property int minimumExpandedHeight: 160
}
