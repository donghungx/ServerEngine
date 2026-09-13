import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var siteData: ({})
    property var dashboardBridge
    property string activeTab: "access"
    property int lastCount: 100
    property var lastOptions: [50, 100, 500]
    property string logPath: ""
    property string logText: ""
    property string loadedSiteId: ""
    property int activeLogTabIndex: 0
    property int activeLastIndex: 1

    function loadLogs() {
        if (!dashboardBridge || !siteData || !siteData.id) {
            return
        }
        var siteId = String(siteData.id)
        logPath = dashboardBridge.siteResponseLogPath(siteId, activeTab, lastCount)
        logText = dashboardBridge.siteResponseLogContent(siteId, activeTab, lastCount)
        loadedSiteId = siteId
    }

    Component.onCompleted: loadLogs()
    onDashboardBridgeChanged: loadLogs()
    onActiveTabChanged: loadLogs()
    onLastCountChanged: loadLogs()
    onSiteDataChanged: {
        var nextId = siteData && siteData.id ? String(siteData.id) : ""
        if (nextId !== loadedSiteId) {
            loadLogs()
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent

        ColumnLayout {
            spacing: 16

            ButtonGroup {
                id: countGroup
                exclusive: true
            }

            Text {
                Layout.fillWidth: true
                text: logPath
                color: Theme.text
                font.pixelSize: 12
                elide: Text.ElideMiddle
                visible: logPath.length > 0
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Strings.t("ip.location.resolution.is.not.enabled.yet")
                color: Theme.muted
                font.pixelSize: 13
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Components.AppScrollEditor {
                    anchors.fill: parent
                    text: logText
                    readOnly: true
                    wrapMode: TextEdit.WrapAnywhere
                    textFormat: TextEdit.PlainText
                    fontFamily: "Menlo"
                    fontPixelSize: 12
                    textColor: Theme.text
                    selectByMouse: true
                    persistentSelection: true
                    contentPadding: 8
                }
            }
        }

        footerRight: RowLayout {
            spacing: 8

            Components.QuickActionButton {
                iconOnly: true
                iconSource: "../icons/lucide/rotate-cw.svg"
                tooltip: Strings.t("refresh")
                onClicked: loadLogs()
            }

            Repeater {
                model: lastOptions

                delegate: Components.AppButton {
                    required property int index
                    property int chipValue: lastOptions[index]
                    text: String(chipValue)
                    checkable: true
                    checked: root.activeLastIndex === index
                    ButtonGroup.group: countGroup
                    highlighted: checked
                    textColor: checked ? "white" : ""
                    onClicked: {
                        root.activeLastIndex = index
                        lastCount = chipValue
                    }
                }
            }
        }

        footerLeft: RowLayout {
            spacing: 8

            Components.AppSwitch {
                checked: root.activeTab === "access"
                onToggled: function(nextChecked) {
                    if (nextChecked) {
                        root.activeTab = "access"
                    } else if (root.activeTab === "access") {
                        root.activeTab = "error"
                    }
                }
            }

            Label {
                text: Strings.t("access.log")
                color: Theme.text
                font.pixelSize: 13
            }

            Components.AppSwitch {
                checked: root.activeTab === "error"
                onToggled: function(nextChecked) {
                    if (nextChecked) {
                        root.activeTab = "error"
                    } else if (root.activeTab === "error") {
                        root.activeTab = "access"
                    }
                }
            }

            Label {
                text: Strings.t("error.log")
                color: Theme.text
                font.pixelSize: 13
            }
        }
    }
}
