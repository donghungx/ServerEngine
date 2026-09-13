import QtQuick
import QtQuick.Controls
import Qt.labs.platform as Native
import "../theme"
import "../i18n"

Rectangle {
    id: root
    property alias text: editor.text
    property alias readOnly: editor.readOnly
    property alias wrapMode: editor.wrapMode
    property alias textFormat: editor.textFormat
    property alias fontFamily: editor.font.family
    property alias fontPixelSize: editor.font.pixelSize
    property alias selectByMouse: editor.selectByMouse
    property alias persistentSelection: editor.persistentSelection
    property alias selectedText: editor.selectedText
    property alias length: editor.length
    property bool undoAvailable: editor.canUndo
    property bool redoAvailable: editor.canRedo
    property alias selectionStart: editor.selectionStart
    property alias selectionEnd: editor.selectionEnd
    property color textColor: Theme.text
    property string placeholderText: ""
    property int contentPadding: 8
    property bool showContextMenu: true
    property bool showEditActions: true
    property bool showEmptyAction: false
    property var emptyAction: null
    property int borderWidth: 1
    property color borderColor: Theme.border
    property bool scrollBarHoldVisible: false

    radius: Theme.radius
    color: Theme.surface
    border.color: borderColor
    border.width: borderWidth
    clip: true

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
        anchors.margins: 0
        clip: true
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
            if (contentItem && contentItem.boundsBehavior !== undefined) {
                contentItem.boundsBehavior = Flickable.StopAtBounds
            }
            if (contentItem && contentItem.boundsMovement !== undefined) {
                contentItem.boundsMovement = Flickable.StopAtBounds
            }
            if (contentItem && contentItem.contentX !== undefined) {
                contentItem.contentX = 0
            }
        }

        TextArea {
            id: editor
            text: ""
            readOnly: true
            wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
            textFormat: TextEdit.PlainText
            color: root.textColor
            font.family: "Menlo"
            font.pixelSize: 12
            selectByMouse: true
            persistentSelection: true
            leftPadding: 0
            rightPadding: 0
            topPadding: 0
            bottomPadding: 0
            textMargin: root.contentPadding
            background: null

            function handleShortcut(event) {
                if (event.matches(StandardKey.Copy)) {
                    editor.copy()
                    event.accepted = true
                    return true
                }
                if (event.matches(StandardKey.SelectAll)) {
                    editor.selectAll()
                    event.accepted = true
                    return true
                }
                return false
            }

            Keys.onShortcutOverride: function(event) {
                editor.handleShortcut(event)
            }

            onTextChanged: {
                if (scroll.contentItem && scroll.contentItem.contentX !== undefined) {
                    scroll.contentItem.contentX = 0
                }
            }

            Keys.onPressed: function(event) {
                editor.handleShortcut(event)
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                enabled: root.showContextMenu
                onTapped: function(_) {
                    editor.forceActiveFocus()
                    nativeMenu.open()
                }
            }

            Native.Menu {
                id: nativeMenu
                Native.MenuItem {
                    text: Strings.t("undo")
                    visible: root.showEditActions
                    enabled: !editor.readOnly && root.undoAvailable
                    onTriggered: editor.undo()
                }
                Native.MenuItem {
                    text: Strings.t("redo")
                    visible: root.showEditActions
                    enabled: !editor.readOnly && root.redoAvailable
                    onTriggered: editor.redo()
                }
                Native.MenuSeparator {
                    visible: root.showEditActions
                }
                Native.MenuItem {
                    text: Strings.t("cut")
                    visible: root.showEditActions
                    enabled: !editor.readOnly && editor.selectedText.length > 0
                    onTriggered: editor.cut()
                }
                Native.MenuItem {
                    text: Strings.t("copy")
                    enabled: editor.selectedText.length > 0
                    onTriggered: editor.copy()
                }
                Native.MenuItem {
                    text: Strings.t("paste")
                    visible: root.showEditActions
                    enabled: !editor.readOnly
                    onTriggered: editor.paste()
                }
                Native.MenuItem {
                    text: Strings.t("delete")
                    visible: root.showEditActions
                    enabled: !editor.readOnly && editor.selectedText.length > 0
                    onTriggered: editor.remove(editor.selectionStart, editor.selectionEnd)
                }
                Native.MenuSeparator {
                    visible: root.showEditActions
                }
                Native.MenuItem {
                    text: Strings.t("select.all")
                    enabled: editor.length > 0
                    onTriggered: editor.selectAll()
                }
                Native.MenuSeparator {
                    visible: root.showEmptyAction
                }
                Native.MenuItem {
                    text: "Empty"
                    visible: root.showEmptyAction
                    enabled: typeof root.emptyAction === "function"
                    onTriggered: root.emptyAction()
                }
            }
        }
    }

    property var editorFlick: scroll.contentItem

    function copy() {
        editor.copy()
    }

    function selectAll() {
        editor.selectAll()
    }

    function cut() {
        editor.cut()
    }

    function paste() {
        editor.paste()
    }

    function undo() {
        editor.undo()
    }

    function redo() {
        editor.redo()
    }

    function remove(start, end) {
        editor.remove(start, end)
    }
}
