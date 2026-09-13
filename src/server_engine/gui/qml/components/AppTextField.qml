import QtQuick
import "../theme"

Rectangle {
    id: root

    signal editingFinished()
    signal accepted()
    signal pressed()
    signal textEdited()
    property alias text: input.text
    property alias placeholderText: placeholder.text
    property alias selectByMouse: input.selectByMouse
    property alias inputMethodHints: input.inputMethodHints
    property alias echoMode: input.echoMode
    property alias validator: input.validator
    property bool readOnly: false
    Keys.priority: Keys.BeforeItem

    function forceActiveFocus() {
        input.forceActiveFocus()
    }

    implicitHeight: 24
    implicitWidth: 260
    radius: 6
    border.width: 1
    border.color: Theme.textFieldBorder
    color: Theme.surface
    opacity: enabled ? 1.0 : 0.6
    clip: true

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        color: Theme.text
        font.pixelSize: 13
        selectionColor: Theme.accentStrong
        selectByMouse: true
        readOnly: root.readOnly
        enabled: root.enabled
        onTextEdited: root.textEdited()
        onActiveFocusChanged: {
            if (activeFocus) {
                root.pressed()
            }
            if (!activeFocus) {
                root.editingFinished()
            }
        }
    }

    Keys.onPressed: function(event) {
        if (
            (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            && !event.isAutoRepeat
        ) {
            root.accepted()
            root.editingFinished()
            event.accepted = true
        }
    }

    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text.length === 0
        color: Theme.muted
        font.pixelSize: 13
    }
}
