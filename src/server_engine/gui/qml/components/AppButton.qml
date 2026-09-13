import QtQuick
import QtQuick.Effects
import "../theme"

Rectangle {
    id: control

    signal clicked()
    signal toggled(bool checked)
    property string text: ""
    property bool accent: false
    property bool highlighted: false
    property bool outline: false
    property bool checkable: false
    property bool checked: false
    property string textColor: ""
    property string iconSource: ""
    property string successIconSource: "icons/lucide/check.svg"
    property string successText: "Saved"
    property bool successActive: false
    property int successDurationMs: 5000
    property int iconSize: 14
    property int spamGuardMs: 450
    property bool hovered: buttonMouseArea.containsMouse
    property bool pressed: buttonMouseArea.pressed
    property bool clickLocked: false
    readonly property string visibleIconSource: successActive ? successIconSource : iconSource
    readonly property string visibleText: successActive ? successText : text

    implicitHeight: 24
    implicitWidth: Math.max(88, label.implicitWidth + (visibleIconSource.length > 0 ? 44 : 24))
    radius: 6
    border.width: 1
    Behavior on width {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    function showSuccess() {
        successActive = true
        successResetTimer.restart()
    }

    function backgroundColor() {
        if (!control.enabled) {
            return Theme.buttonDisabledBackground
        }
        if (successActive) {
            if (control.pressed) {
                return Qt.darker(Theme.success, 1.1)
            }
            if (control.hovered) {
                return Qt.lighter(Theme.success, 1.08)
            }
            return Theme.success
        }
        if (control.outline) {
            return Theme.buttonOutlineBackground
        }
        if (control.accent || control.highlighted || (control.checkable && control.checked)) {
            return control.pressed
                ? Theme.buttonPrimaryPressedBackground
                : (control.hovered ? Theme.buttonPrimaryHoverBackground : Theme.buttonPrimaryBackground)
        }
        return control.pressed
            ? Theme.buttonNeutralPressedBackground
            : (control.hovered ? Theme.buttonNeutralHoverBackground : Theme.buttonNeutralBackground)
    }

    function borderColor() {
        if (!control.enabled) {
            return Theme.buttonDisabledBorder
        }
        if (successActive) {
            return Theme.success
        }
        if (control.outline) {
            return Theme.buttonOutlineBorder
        }
        return control.color
    }

    function resolvedTextColor() {
        if (!control.enabled) {
            return Theme.buttonDisabledText
        }
        if (successActive) {
            return "#ffffff"
        }
        if (control.outline && control.textColor.length > 0) {
            return control.textColor
        }
        if (control.outline) {
            return Theme.buttonOutlineText
        }
        if ((control.accent || control.highlighted || (control.checkable && control.checked)) && control.textColor.length > 0) {
            return control.textColor
        }
        return (control.accent || control.highlighted || (control.checkable && control.checked))
            ? Theme.buttonPrimaryText
            : Theme.buttonNeutralText
    }

    function resolvedIconSource(source) {
        var icon = String(source || "")
        if (icon.length === 0) {
            return ""
        }
        if (icon.indexOf(":/") === 0
            || icon.indexOf("qrc:/") === 0
            || icon.indexOf("file:/") === 0) {
            return icon
        }
        if (icon.indexOf("icons/") === 0) {
            return "../" + icon
        }
        return icon
    }

    color: backgroundColor()
    border.color: borderColor()

    function triggerClick() {
        if (!control.enabled || control.clickLocked) {
            return
        }
        control.clickLocked = true
        clickGuardTimer.restart()
        if (control.checkable) {
            control.checked = !control.checked
            control.toggled(control.checked)
        }
        control.clicked()
    }

    Row {
        anchors.centerIn: parent
        spacing: 6

        Item {
            width: control.visibleIconSource.length > 0 ? control.iconSize : 0
            height: control.iconSize
            opacity: control.visibleIconSource.length > 0 ? 1 : 0
            Behavior on width {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            Image {
                id: iconImage
                anchors.centerIn: parent
                width: control.iconSize
                height: control.iconSize
                sourceSize.width: control.iconSize
                sourceSize.height: control.iconSize
                fillMode: Image.PreserveAspectFit
                smooth: true
                source: control.resolvedIconSource(control.visibleIconSource)
                visible: false
            }

            MultiEffect {
                anchors.centerIn: parent
                width: control.iconSize
                height: control.iconSize
                source: iconImage
                colorization: 1.0
                colorizationColor: label.color
                brightness: 1.0
            }
        }

        Text {
            id: label
            text: control.visibleText
            color: control.resolvedTextColor()
            font.pixelSize: 12
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: buttonMouseArea
        anchors.fill: parent
        enabled: control.enabled
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        onClicked: control.triggerClick()
    }

    Timer {
        id: clickGuardTimer
        interval: control.spamGuardMs
        repeat: false
        onTriggered: control.clickLocked = false
    }

    Timer {
        id: successResetTimer
        interval: control.successDurationMs
        repeat: false
        onTriggered: control.successActive = false
    }
}
