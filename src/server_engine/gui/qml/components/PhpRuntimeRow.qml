import QtQuick
import "../theme"
import QtQuick.Controls
import Qt.labs.platform as Native
import "." as Components
import "../i18n"

Rectangle {
    id: root
    required property var rowData
    required property var dashboardBridge
    signal settingsSelected()
    signal phpIniSelected()

    readonly property bool nativeMenuIconsSupported: root.dashboardBridge
        && root.dashboardBridge.macOS26OrLater

    function runtimePath() {
        return String(rowData.home || rowData.php_path || "")
    }

    function phpIniPath() {
        return String(rowData.ini_dir || "") + "/php.ini"
    }

    color: "transparent"
    border.width: 0

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        Item {
            width: 280
            height: parent.height

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 42
                    height: 22
                    radius: 7
                    color: Theme.phpBadgeBackground
                    border.width: 1
                    border.color: Theme.phpBadgeBorder

                    Text {
                        anchors.centerIn: parent
                        text: Strings.t("php")
                        color: Theme.text
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }

                Column {
                    spacing: 4
                    width: 232

                    Text {
                        text: Strings.t("php") + " " + rowData.version
                        color: Theme.text
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: rowData.label
                        color: Theme.muted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }
        }

        Item {
            width: 140
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: rowData.status
                color: String(rowData.status || "") === "Active" ? Theme.phpActiveStatusText : Theme.text
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        Item {
            width: Math.max(0, parent.width - 280 - 140)
            height: parent.height

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Components.QuickActionButton {
                    text: Strings.t("php.ini")
                    iconSource: "../icons/lucide/file-text.svg"
                    onClicked: root.phpIniSelected()
                }

                Components.QuickActionButton {
                    text: Strings.t("settings")
                    iconSource: "../icons/lucide/settings.svg"
                    onClicked: root.settingsSelected()
                }

                Components.QuickActionButton {
                    id: moreButton
                    text: ""
                    iconSource: "../icons/lucide/ellipsis-vertical.svg"
                    tooltip: "Options"
                    onClicked: {
                        moreMenu.runtimePath = root.runtimePath()
                        moreMenu.executionPath = String(rowData.php_path || "")
                        moreMenu.phpIniPath = root.phpIniPath()
                        moreMenu.open(moreButton)
                    }
                }

                Native.Menu {
                    id: moreMenu
                    property string runtimePath: ""
                    property string executionPath: ""
                    property string phpIniPath: ""

                    Native.MenuItem {
                        text: "Copy execution path"
                        enabled: moreMenu.executionPath.length > 0
                        icon.name: root.nativeMenuIconsSupported ? "edit-copy" : ""
                        icon.source: root.nativeMenuIconsSupported ? "../icons/lucide/file-text.svg" : ""
                        onTriggered: {
                            if (root.dashboardBridge && root.dashboardBridge.copyTextToClipboard) {
                                root.dashboardBridge.copyTextToClipboard(moreMenu.executionPath)
                            }
                        }
                    }

                    Native.MenuItem {
                        text: "Copy php.ini Path"
                        enabled: moreMenu.phpIniPath.length > 0
                        icon.name: root.nativeMenuIconsSupported ? "edit-copy" : ""
                        icon.source: root.nativeMenuIconsSupported ? "../icons/lucide/file-text.svg" : ""
                        onTriggered: {
                            if (root.dashboardBridge && root.dashboardBridge.copyTextToClipboard) {
                                root.dashboardBridge.copyTextToClipboard(moreMenu.phpIniPath)
                            }
                        }
                    }

                    Native.MenuItem {
                        text: "Reveal php.ini in Finder"
                        enabled: moreMenu.phpIniPath.length > 0
                        icon.name: root.nativeMenuIconsSupported ? "folder" : ""
                        icon.source: root.nativeMenuIconsSupported ? "../icons/lucide/folder-open.svg" : ""
                        onTriggered: {
                            if (root.dashboardBridge && root.dashboardBridge.revealInFinder) {
                                root.dashboardBridge.revealInFinder(moreMenu.phpIniPath)
                            }
                        }
                    }

                    Native.MenuItem {
                        text: "Open with Terminal"
                        enabled: moreMenu.runtimePath.length > 0
                        icon.name: root.nativeMenuIconsSupported ? "terminal" : ""
                        icon.source: root.nativeMenuIconsSupported ? "../icons/lucide/terminal.svg" : ""
                        onTriggered: {
                            if (root.dashboardBridge && root.dashboardBridge.openPathInTerminal) {
                                root.dashboardBridge.openPathInTerminal(moreMenu.runtimePath)
                            }
                        }
                    }

                    Native.MenuSeparator {}

                    Native.MenuItem {
                        text: Strings.t("settings")
                        icon.name: root.nativeMenuIconsSupported ? "preferences-system" : ""
                        icon.source: root.nativeMenuIconsSupported ? "../icons/lucide/settings.svg" : ""
                        onTriggered: root.settingsSelected()
                    }
                }
            }
        }

    }
}
