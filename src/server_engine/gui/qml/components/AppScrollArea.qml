import QtQuick
import QtQuick.Controls
import "../theme"

Rectangle {
    id: root
    default property alias contentData: contentHost.data
    property int viewportMargins: 0
    property bool clipContent: true
    property bool showBorder: false
    property bool scrollBarHoldVisible: false
    readonly property real availableWidth: scroll.availableWidth
    property var flick: scroll.contentItem

    radius: showBorder ? Theme.radius : 0
    color: "transparent"
    border.width: showBorder ? 1 : 0
    border.color: Theme.border

    Timer {
        id: scrollBarHideTimer
        interval: 1200
        repeat: false
        onTriggered: root.scrollBarHoldVisible = false
    }

    function refreshScrollBarVisibility() {
        if (vBar.active || vBar.hovered || vBar.pressed) {
            root.scrollBarHoldVisible = true
            scrollBarHideTimer.restart()
        } else {
            scrollBarHideTimer.restart()
        }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: viewportMargins
        clip: root.clipContent
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            id: vBar
            policy: ScrollBar.AsNeeded
            hoverEnabled: true
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.rightMargin: 2
            width: 7
            opacity: (active || hovered || pressed || root.scrollBarHoldVisible) ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 140 }
            }
            onActiveChanged: root.refreshScrollBarVisibility()
            onHoveredChanged: root.refreshScrollBarVisibility()
            onPressedChanged: root.refreshScrollBarVisibility()
            background: Rectangle {
                implicitWidth: 7
                implicitHeight: 100
                radius: 3.5
                color: Theme.scrollBarTrack
                opacity: 0.55
            }
            contentItem: Rectangle {
                implicitWidth: 7
                implicitHeight: 32
                radius: 3.5
                color: Theme.scrollBarThumb
                opacity: vBar.pressed ? 1.0 : 0.92
            }
        }

        onContentItemChanged: {
            if (contentItem && contentItem.flickableDirection !== undefined) {
                contentItem.flickableDirection = Flickable.VerticalFlick
            }
            if (contentItem && contentItem.contentX !== undefined) {
                contentItem.contentX = 0
            }
        }

        Column {
            id: contentHost
            width: scroll.availableWidth !== undefined ? scroll.availableWidth : scroll.width
            spacing: 0
        }
    }
}
