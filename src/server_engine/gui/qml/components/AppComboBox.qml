import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Window
import Qt.labs.platform as Native
import "../theme"

Rectangle {
    id: root

    signal activated(int index)
    property var model: []
    property string textRole: ""
    property bool useNativeMenu: Qt.platform.os === "osx"
    property bool editable: false
    property string editText: ""
    property int currentIndex: (model && model.length > 0) ? 0 : -1
    readonly property string currentText: textForIndex(currentIndex)
    function find(value) {
        var target = String(value === undefined || value === null ? "" : value)
        for (var i = 0; i < (model ? model.length : 0); i++) {
            if (textForIndex(i) === target) {
                return i
            }
        }
        return -1
    }
    function textForIndex(index) {
        if (!model || index < 0 || index >= model.length) {
            return ""
        }
        var item = model[index]
        if (typeof item === "string") {
            return item
        }
        if (textRole.length > 0 && item && item[textRole] !== undefined) {
            return String(item[textRole])
        }
        if (item && item.label !== undefined) {
            return String(item.label)
        }
        return String(item)
    }
    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }
    function positionPopup() {
        if (!popup.visible) {
            return
        }
        var win = root.Window.window
        var overlay = popup.parent
        if (!win || !overlay) {
            popup.x = -8
            popup.y = -8
            return
        }
        var localPos = root.mapToItem(overlay, 0, 0)
        var desiredX = localPos.x - 8
        var desiredY = localPos.y - 8
        var maxX = Math.max(0, overlay.width - popup.width)
        var maxY = Math.max(0, overlay.height - popup.height)
        popup.x = clamp(desiredX, 0, maxX)
        popup.y = clamp(desiredY, 0, maxY)
    }

    onModelChanged: {
        if (!model || model.length === 0) {
            currentIndex = -1
        } else if (currentIndex < 0 || currentIndex >= model.length) {
            currentIndex = 0
        }
    }

    implicitHeight: 24
    implicitWidth: 260
    radius: 6
    border.width: 0
    color: Theme.comboBoxBackground
    opacity: enabled ? 1.0 : 0.6

    Text {
        visible: !root.editable
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - 32)
        text: root.currentText
        color: Theme.text
        font.pixelSize: 12
        elide: Text.ElideRight
        font.weight: Font.Medium
    }

    Rectangle {
        width: 12
        height: 12
        color: "transparent"
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter

        Image {
            id: arrowSourceImage
            anchors.centerIn: parent
            width: 16
            height: 16
            sourceSize.width: 16
            sourceSize.height: 16
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "../icons/lucide/chevrons-up-down.svg"
            visible: false
        }

        MultiEffect {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: arrowSourceImage
            colorization: 1.0
            colorizationColor: Theme.text
            brightness: 1.0
        }
    }

    TextInput {
        visible: root.editable
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.text
        font.pixelSize: 12
        text: root.editText.length > 0 ? root.editText : root.currentText
        onTextEdited: root.editText = text
    }

    MouseArea {
        id: triggerArea
        property bool pressedWhenPopupVisible: false
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: pressedWhenPopupVisible = !root.useNativeMenu && popup.visible
        onClicked: {
            if (root.useNativeMenu) {
                nativeMenu.open(root)
            } else {
                if (pressedWhenPopupVisible) {
                    popup.close()
                } else {
                    Qt.callLater(function() {
                        popup.open()
                    })
                }
            }
        }
    }

    Popup {
        id: popup
        x: -8
        y: -8
        width: root.width
        padding: 2
        modal: false
        focus: true
        parent: Overlay.overlay
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: root.positionPopup()
        background: Rectangle {
            radius: 4
            color: Theme.comboBoxBackground
            border.color: Theme.border
            border.width: 1
        }
        contentItem: ListView {
            implicitHeight: Math.min(200, contentHeight)
            model: root.model
            clip: true
            delegate: Rectangle {
                required property int index
                width: ListView.view.width
                height: 24
                color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 1
                    anchors.rightMargin: 1
                    radius: 4
                    color: root.currentIndex === index ? Theme.comboBoxSelectedBackground : "transparent"
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 20)
                    text: root.textForIndex(index)
                    color: Theme.text
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: parent.children[0].color = Theme.comboBoxSelectedBackground
                    onExited: parent.children[0].color = root.currentIndex === index ? Theme.comboBoxSelectedBackground : "transparent"
                    onClicked: {
                        root.currentIndex = index
                        root.activated(index)
                        popup.close()
                    }
                }
            }
        }
    }

    Connections {
        target: root.Window.window
        function onWidthChanged() { root.positionPopup() }
        function onHeightChanged() { root.positionPopup() }
        function onXChanged() { root.positionPopup() }
        function onYChanged() { root.positionPopup() }
    }

    Native.Menu {
        id: nativeMenu
        minimumWidth: root.width
    }

    Instantiator {
        id: nativeMenuItems
        model: root.model ? root.model.length : 0
        delegate: Native.MenuItem {
            required property int index
            text: root.textForIndex(index)
            checkable: true
            checked: root.currentIndex === index
            onTriggered: {
                root.currentIndex = index
                root.activated(index)
            }
        }
        onObjectAdded: function(index, object) {
            nativeMenu.insertItem(index, object)
        }
        onObjectRemoved: function(index, object) {
            nativeMenu.removeItem(object)
        }
    }
}
