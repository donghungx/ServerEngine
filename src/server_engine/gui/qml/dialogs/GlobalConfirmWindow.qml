import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: root
    required property var window

    property string confirmActionId: ""
    property var confirmPayload: ({})
    property string titleText: Strings.t("confirm")
    property string messageText: ""
    property string confirmText: Strings.t("confirm")
    property string cancelText: Strings.t("cancel")
    readonly property int panelMargin: window && window.bridge && window.bridge.macOS26OrLater ? 20 : 12

    signal confirmed(string actionId, var payload)
    signal canceled()

    visible: window ? window.globalConfirmOpen : false
    width: 400
    height: 108
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: titleText
    color: "transparent"
    modality: Qt.WindowModal
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.FramelessWindowHint

    onVisibleChanged: {
        if (visible) {
            raise()
        }
    }

    Connections {
        target: window ? window.globalConfirmTransientParent : null
        function onActiveChanged() {
            if (window && window.globalConfirmOpen) {
                root.raise()
            }
        }
    }

    onClosing: function(closeEvent) {
        closeEvent.accepted = true
        if (window) {
            window.globalConfirmOpen = false
        }
        canceled()
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        context: Qt.WindowShortcut
        onActivated: {
            if (window) {
                window.globalConfirmOpen = false
            }
            canceled()
        }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: window && window.bridge && window.bridge.macOS26OrLater ? 20 : 12
        color: Theme.surface
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) {
                root.startSystemMove()
                mouse.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.panelMargin
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: messageText
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    font.weight: Font.Medium
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 24

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Components.AppButton {
                        text: cancelText
                        onClicked: {
                            if (window) {
                                window.globalConfirmOpen = false
                            }
                            root.canceled()
                        }
                    }

                    Components.AppButton {
                        text: confirmText
                        highlighted: true
                        textColor: "white"
                        onClicked: {
                            if (window) {
                                window.globalConfirmOpen = false
                            }
                            root.confirmed(root.confirmActionId, root.confirmPayload)
                        }
                    }
                }
            }
        }
    }
}
