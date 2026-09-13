import QtQuick
import QtQuick.Effects
import "../components" as Components
import "../i18n"
import "../theme"

Rectangle {
    id: nativeTitleRow

    signal appSettingsRequested()
    signal moveRequested()
    signal maximizeToggleRequested()

    required property real topPadding
    required property var dashboardBridge
    required property var appWindow
    property bool movePending: false
    property int navButtonWidth: 32
    property int navButtonHeight: 28
    property int navIconSize: 24

    function resolvedNavIconSource(iconSource) {
        if (!iconSource || iconSource.length === 0) {
            return ""
        }
        if (iconSource.indexOf(":/") === 0
            || iconSource.indexOf("qrc:/") === 0
            || iconSource.indexOf("file:/") === 0) {
            return iconSource
        }
        if (iconSource.indexOf("icons/") === 0) {
            return "../" + iconSource
        }
        return iconSource
    }

    y: -topPadding
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 56
    color: "transparent"
    z: 50

    Row {
        id: navigationActionRow
        anchors.left: parent.left
        anchors.leftMargin: 196
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        height: navButtonHeight

        Rectangle {
            width: navButtonWidth
            height: navButtonHeight
            radius: 6
            color: backHover.containsMouse ? (Theme.dark ? "#202838" : "#eef1f5") : "transparent"
            opacity: appWindow.canNavigateBack ? 1.0 : 0.45

            Image {
                id: backIcon
                anchors.centerIn: parent
                width: navIconSize
                height: navIconSize
                source: nativeTitleRow.resolvedNavIconSource("icons/lucide/chevron-left.svg")
                visible: false
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            MultiEffect {
                anchors.fill: backIcon
                source: backIcon
                width: navIconSize
                height: navIconSize
                colorization: 1.0
                colorizationColor: Theme.text
                brightness: 1.0
            }

            MouseArea {
                id: backHover
                anchors.fill: parent
                enabled: appWindow.canNavigateBack
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: appWindow.navigateBack()
            }
        }

        Rectangle {
            width: navButtonWidth
            height: navButtonHeight
            radius: 6
            color: forwardHover.containsMouse ? (Theme.dark ? "#202838" : "#eef1f5") : "transparent"
            opacity: appWindow.canNavigateForward ? 1.0 : 0.45

            Image {
                id: forwardIcon
                anchors.centerIn: parent
                width: navIconSize
                height: navIconSize
                source: nativeTitleRow.resolvedNavIconSource("icons/lucide/chevron-right.svg")
                visible: false
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            MultiEffect {
                anchors.fill: forwardIcon
                source: forwardIcon
                width: navIconSize
                height: navIconSize
                colorization: 1.0
                colorizationColor: Theme.text
                brightness: 1.0
            }

            MouseArea {
                id: forwardHover
                anchors.fill: parent
                enabled: appWindow.canNavigateForward
                hoverEnabled: true
                onClicked: appWindow.navigateForward()
            }
        }
    }

    Row {
        id: globalActionRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 16
        spacing: 8

        Components.HeaderIconButton {
            label: Strings.t("settings")
            iconSource: "icons/lucide/settings.svg"
            onClicked: nativeTitleRow.appSettingsRequested()
        }

        Components.HeaderIconButton {
            label: dashboardBridge.globalStackBusy
                ? (dashboardBridge.globalStackActionLabel.indexOf("Stop") === 0 ? "Stopping..." : "Starting...")
                : dashboardBridge.globalStackActionLabel
            iconSource: "icons/lucide/power-accent.svg"
            primary: true
            enabled: !dashboardBridge.globalStackBusy
            onClicked: dashboardBridge.toggleGlobalStack()
        }

        Components.HeaderIconButton {
            label: Strings.t("restart")
            iconSource: "icons/lucide/rotate-cw.svg"
            enabled: !dashboardBridge.globalStackBusy
            onClicked: dashboardBridge.restartStack()
        }
    }

    MouseArea {
        id: dragArea
        anchors.left: navigationActionRow.right
        anchors.right: globalActionRow.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onPressed: function(_mouse) {
            nativeTitleRow.movePending = true
            nativeTitleRow.moveRequested()
        }
        onDoubleClicked: {
            nativeTitleRow.movePending = false
            nativeTitleRow.maximizeToggleRequested()
        }
        onPositionChanged: function(_mouse) {
            if (pressed && nativeTitleRow.movePending) {
                nativeTitleRow.moveRequested()
            }
        }
        onReleased: nativeTitleRow.movePending = false
        onCanceled: nativeTitleRow.movePending = false
    }
}
