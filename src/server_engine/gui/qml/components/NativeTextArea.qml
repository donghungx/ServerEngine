import QtQuick
import QtQuick.Controls
import Qt.labs.platform as Native
import "../i18n"

TextArea {
    id: control
    property bool nativeContextMenuEnabled: true

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: control.nativeContextMenuEnabled
        onTapped: function(eventPoint) {
            control.forceActiveFocus()
            nativeContextMenu.open()
        }
    }

    Native.Menu {
        id: nativeContextMenu

        Native.MenuItem {
            text: Strings.t("undo")
            enabled: !control.readOnly && control.canUndo
            onTriggered: control.undo()
        }
        Native.MenuItem {
            text: Strings.t("redo")
            enabled: !control.readOnly && control.canRedo
            onTriggered: control.redo()
        }
        Native.MenuSeparator {}
        Native.MenuItem {
            text: Strings.t("cut")
            enabled: !control.readOnly && control.selectedText.length > 0
            onTriggered: control.cut()
        }
        Native.MenuItem {
            text: Strings.t("copy")
            enabled: control.selectedText.length > 0
            onTriggered: control.copy()
        }
        Native.MenuItem {
            text: Strings.t("paste")
            enabled: !control.readOnly
            onTriggered: control.paste()
        }
        Native.MenuSeparator {}
        Native.MenuItem {
            text: Strings.t("select.all")
            enabled: control.length > 0
            onTriggered: control.selectAll()
        }
    }
}
