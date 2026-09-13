import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Native
import "../theme"
import "../i18n"
import "." as Components

Item {
    id: root

    property string title: Strings.t("logs")
    property string description: ""
    property string emptyText: "No log yet."
    property string logPath: ""
    property
    var logPathProvider: null
    property
    var logContentProvider: null
    property
    var openLogPathHandler: null
    property bool tailMode: true
    property bool showLatest: true
    property int lineCount: 100
    property int lineCountIndex: 1
    property
    var lineOptions: ["50", "100", "200", "500", "1000"]
    property string rawLogText: ""
    property string logText: ""

    function orderedLogText(sourceText) {
        var source = String(sourceText || "")
        if (!showLatest || source.length === 0) {
            return source
        }
        var keepTrailingNewline = source.charAt(source.length - 1) === "\n"
        var lines = source.split("\n")
        if (keepTrailingNewline && lines.length > 0 && lines[lines.length - 1] === "") {
            lines.pop()
        }
        lines.reverse()
        var output = lines.join("\n")
        if (keepTrailingNewline) {
            output += "\n"
        }
        return output
    }

    function refreshLogText() {
        logText = rawLogText.length > 0 ? orderedLogText(rawLogText) : emptyText
    }

    function loadLogs() {
        if (typeof logPathProvider === "function") {
            logPath = String(logPathProvider() || "")
        }
        if (typeof logContentProvider !== "function") {
            rawLogText = ""
            refreshLogText()
            return
        }
        rawLogText = String(logContentProvider(lineCount, tailMode) || "")
        refreshLogText()
    }

    function openLogPath() {
        if (logPath.length === 0 || typeof openLogPathHandler !== "function") {
            return
        }
        openLogPathHandler(logPath)
    }

    Component.onCompleted: deferredLoadTimer.restart()
    onTailModeChanged: loadLogs()
    onShowLatestChanged: refreshLogText()
    onLineCountChanged: loadLogs()
    onLogContentProviderChanged: loadLogs()
    onLogPathProviderChanged: loadLogs()

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"
        contentMargins: 0
        contentSpacing: 10
        footerRightMargin: 0
        footerBottomMargin: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: root.description
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                visible: root.description.length > 0
                font.weight: Font.Medium
            }

            Components.AppScrollEditor {
                id: logEditor
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.maximumHeight: 520
                text: root.logText
                textColor: Theme.text
                fontPixelSize: 12
                fontFamily: "Menlo"
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                readOnly: true
                selectByMouse: true
            }
        }

        footerLeft: Row {
            spacing: 14

            Row {
                spacing: 8

                Components.AppSwitch {
                    checked: root.tailMode
                    onToggled: function(checked) {
                        root.tailMode = checked
                    }
                }

                Label {
                    text: Strings.t("tail.mode")
                    color: Theme.text
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: 8

                Components.AppSwitch {
                    checked: root.showLatest
                    onToggled: function(checked) {
                        root.showLatest = checked
                    }
                }

                Label {
                    text: Strings.t("show.latest")
                    color: Theme.text
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        footerRight: Row {
            spacing: 8

            Components.AppComboBox {
                width: 88
                model: root.lineOptions
                currentIndex: root.lineCountIndex
                onActivated: function(index) {
                    root.lineCountIndex = index
                    root.lineCount = parseInt(currentText, 10)
                }
            }

            Components.QuickActionButton {
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: Strings.t("reload")
                onClicked: loadLogs()
            }

            Components.QuickActionButton {
                iconSource: "../icons/lucide/file-text.svg"
                tooltip: Strings.t("reveal.in.finder")
                visible: root.logPath.length > 0 && typeof openLogPathHandler === "function"
                onClicked: openLogPath()
            }
        }
    }

    Native.Menu {
        id: logMenu
        Native.MenuItem {
            text: Strings.t("copy")
            enabled: logEditor.selectedText.length > 0
            onTriggered: logEditor.copy()
        }
        Native.MenuSeparator {}
        Native.MenuItem {
            text: Strings.t("select.all")
            enabled: logEditor.length > 0
            onTriggered: logEditor.selectAll()
        }
    }

    Timer {
        id: deferredLoadTimer
        interval: 0
        repeat: false
        onTriggered: loadLogs()
    }
}