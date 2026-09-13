import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Native
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot: ({})
    property var dashboardBridge: ({})
    property var runtimeWindow

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (pageRoot && pageRoot.dashboardBridge) {
            return pageRoot.dashboardBridge
        }
        return ({})
    }

    Column {
        anchors.fill: parent
        spacing: 14
        Row {
            spacing: 10
            Components.AppButton {
                text: pageRoot.slowLogEnabled ? "Enabled" : "Disabled"
                checkable: true
                checked: pageRoot.slowLogEnabled
                highlighted: checked
                textColor: checked ? "white" : Theme.text
                onClicked: pageRoot.slowLogEnabled = !pageRoot.slowLogEnabled
            }
            Components.AppButton {
                text: Strings.t("refresh")
                onClicked: bridge().refreshMongodbRuntime && bridge().refreshMongodbRuntime()
            }
        }
        Row {
            spacing: 14
            Column {
                spacing: 6
                Text { text: Strings.t("long.query.time.seconds"); color: Theme.muted; font.pixelSize: 12 }
                Rectangle {
                    width: 180; height: 40; radius: Theme.radius
                    color: Theme.surface; border.color: Theme.border; border.width: 1
                    TextInput {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.pixelSize: 13
                        text: String(pageRoot.slowLogLongQueryTime || "")
                        onTextChanged: pageRoot.slowLogLongQueryTime = text
                    }
                }
            }
            Column {
                spacing: 6
                Text { text: Strings.t("log.queries.not.using.indexes"); color: Theme.muted; font.pixelSize: 12 }
                Rectangle {
                    width: 180; height: 40; radius: Theme.radius
                    color: Theme.surface; border.color: Theme.border; border.width: 1
                    Components.AppComboBox {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 16
                        model: ["On", "Off"]
                        currentIndex: pageRoot.slowLogNotUsingIndexes === "Off" ? 1 : 0
                        onCurrentTextChanged: pageRoot.slowLogNotUsingIndexes = currentText
                    }
                }
            }
        }
        Text { text: Strings.t("slow.log.output"); color: Theme.text; font.pixelSize: 14; font.weight: Font.Medium }
        Rectangle {
            width: parent.width; height: 340; radius: Theme.radius
            color: "#262b33"; border.color: "#1d242b"; border.width: 1
                Components.AppScrollEditor {
                    id: slowLogText
                    anchors.fill: parent
                    anchors.margins: 12
                    text: String(bridge().mongodbRuntimeLog || "").length > 0
                        ? String(bridge().mongodbRuntimeLog || "")
                        : "# Time: 2026-04-23T04:33:30Z\n# Query_time: 3.018004  Lock_time: 0.000038  Rows_sent: 20  Rows_examined: 11698540\nSET timestamp=1776910466;\nSELECT hash, title, artist, count FROM lyrics_lyrics LIMIT 11698520, 20;"
                    textColor: Theme.text
                    fontPixelSize: 12
                    fontFamily: "Menlo"
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                readOnly: true
                selectByMouse: true
            }
        }
    }

    Native.Menu {
        id: mongodbSlowLogMenu
        Native.MenuItem {
            text: Strings.t("copy")
            enabled: String(slowLogText.selectedText || "").length > 0
            onTriggered: slowLogText.copy()
        }
        Native.MenuSeparator {}
        Native.MenuItem {
            text: Strings.t("select.all")
            enabled: String(slowLogText.text || "").length > 0
            onTriggered: slowLogText.selectAll()
        }
    }
}
