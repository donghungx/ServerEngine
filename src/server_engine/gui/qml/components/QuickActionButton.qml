import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "../theme"
import "." as Components
import "../i18n"

Rectangle {
    id: root

    property string text: ""
    property string iconSource: ""
    property string tooltip: ""
    property bool danger: false
    property int iconSize: 14
    property bool useCustomHoverBackground: false
    property color hoverBackgroundColor: "transparent"
    property bool iconOnly: text.length === 0
    property bool clickToShowTooltip: false
    property bool tooltipPinned: false

    signal clicked()

    implicitWidth: iconOnly
        ? Math.max(24, iconSize + 10)
        : Math.max(58, (label.implicitWidth + (iconSource.length > 0 ? iconSize + 4 + 14 : 0) + 16))
    implicitHeight: iconOnly ? Math.max(24, iconSize + 10) : 26
    width: implicitWidth
    height: implicitHeight
    radius: iconOnly ? Math.min(width, height) / 2 : 6
    border.width: 0
    border.color: "transparent"
    opacity: root.enabled ? 1.0 : 0.42

    function resolvedIconSource() {
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

    color: {
        if (!root.enabled) {
            return "transparent"
        }
        if (!actionArea.containsMouse) {
            return "transparent"
        }
        if (useCustomHoverBackground) {
            return hoverBackgroundColor
        }
        if (danger) {
            return Theme.quickActionDangerHoverBackground
        }
        return Theme.quickActionHoverBackground
    }

    Row {
        anchors.centerIn: parent
        spacing: 6

        Image {
            id: iconSourceImage
            visible: false
            source: root.resolvedIconSource()
            width: root.iconSize
            height: root.iconSize
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            fillMode: Image.PreserveAspectFit
        }

        MultiEffect {
            visible: root.iconSource.length > 0
            width: root.iconSize
            height: root.iconSize
            source: iconSourceImage
            colorization: 1.0
            colorizationColor: root.danger ? Theme.quickActionDangerIcon : Theme.text
            brightness: 1.0
        }

        Text {
            id: label
            visible: root.text.length > 0
            text: root.text
            color: root.danger ? Theme.quickActionDangerText : Theme.text
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: actionArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        onClicked: root.clicked()
        onReleased: {
            if (root.clickToShowTooltip) {
                root.tooltipPinned = !root.tooltipPinned
            }
        }
    }

    Components.AppToolTip {
        visible: root.tooltip.length > 0 && (actionArea.containsMouse || root.tooltipPinned)
        delay: 450
        text: root.tooltip
    }
}
