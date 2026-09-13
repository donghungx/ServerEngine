import QtQuick
import "../../theme"

Rectangle {
    id: bottomMailPanel

    signal hideRequested()

    required property var dashboardBridge
    required property bool bottomMailOpen
    required property var statusBarItem
    required property var appWindow
    property bool dockMode: false

    readonly property int minimumExpandedHeight: 80
    property bool mailResizing: false

    anchors {
        left: parent.left
        right: parent.right
        bottom: dockMode ? parent.bottom : statusBarItem.top
    }
    height: dockMode
        ? (parent ? parent.height : 0)
        : (bottomMailOpen ? Math.min(sharedMailHeight(), mailMaxExpandedHeight()) : 0)
    color: Theme.surfaceAlt
    clip: true
    visible: dockMode ? true : height > 0

    Behavior on height {
        enabled: !bottomMailPanel.mailResizing
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    function requestRefreshMailbox() {
        if (mailPanel && mailPanel.requestRefreshMailbox) {
            mailPanel.requestRefreshMailbox()
        }
    }

    Item {
        id: mailResizeTopHandle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 6
        z: 100
        visible: !bottomMailPanel.dockMode

        MouseArea {
            id: mailResizeTopMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            property real dragStartSceneY: 0
            property int dragStartHeight: 0

            onPressed: function(mouse) {
                bottomMailPanel.mailResizing = true
                dragStartSceneY = mailResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                dragStartHeight = sharedMailHeight()
                mouse.accepted = true
            }

            onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) {
                    return
                }
                var currentSceneY = mailResizeTopHandle.mapToItem(null, mouse.x, mouse.y).y
                setSharedMailHeight(dragStartHeight + (dragStartSceneY - currentSceneY))
            }

            onReleased: function(mouse) {
                bottomMailPanel.mailResizing = false
                if (bottomMailPanel.dashboardBridge && bottomMailPanel.dashboardBridge.saveBottomTerminalPanelHeight) {
                    bottomMailPanel.dashboardBridge.saveBottomTerminalPanelHeight(sharedMailHeight())
                }
                mouse.accepted = true
            }

            onCanceled: {
                bottomMailPanel.mailResizing = false
            }
        }
    }

    MailPanel {
        id: mailPanel
        anchors.fill: parent
        dashboardBridge: bottomMailPanel.dashboardBridge
        panelOpen: bottomMailPanel.bottomMailOpen
        onHideRequested: bottomMailPanel.hideRequested()
    }

    function sharedMailHeight() {
        if (bottomMailPanel.appWindow && bottomMailPanel.appWindow.bottomPanelHeight !== undefined) {
            return Math.max(minimumExpandedHeight, Number(bottomMailPanel.appWindow.bottomPanelHeight || minimumExpandedHeight))
        }
        return minimumExpandedHeight
    }

    function mailMaxExpandedHeight() {
        return Math.max(
            minimumExpandedHeight,
            Math.floor(((parent && parent.height) ? parent.height : 0) * 2 / 3)
        )
    }

    function clampMailHeight(nextHeight) {
        return Math.max(
            minimumExpandedHeight,
            Math.min(mailMaxExpandedHeight(), Math.floor(nextHeight))
        )
    }

    function setSharedMailHeight(nextHeight) {
        var clamped = clampMailHeight(nextHeight)
        if (bottomMailPanel.appWindow && bottomMailPanel.appWindow.bottomPanelHeight !== undefined) {
            bottomMailPanel.appWindow.bottomPanelHeight = clamped
        }
    }
}
