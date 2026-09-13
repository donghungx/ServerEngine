import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    id: root

    property var pageRoot
    property var dashboardBridge

    function loadModules() {
        if (!dashboardBridge || !pageRoot || String(pageRoot.editingNodeProjectId || "").length === 0) {
            return
        }
        dashboardBridge.requestNodeProjectModulesAsync(pageRoot.editingNodeProjectId)
    }

    function reloadModules() {
        if (!dashboardBridge || !pageRoot || String(pageRoot.editingNodeProjectId || "").length === 0) {
            return
        }
        dashboardBridge.reloadNodeProjectModulesAsync(pageRoot.editingNodeProjectId)
    }

    function installDependencies() {
        if (!dashboardBridge || !pageRoot || String(pageRoot.editingNodeProjectId || "").length === 0) {
            return
        }
        dashboardBridge.installNodeProjectDependenciesAsync(pageRoot.editingNodeProjectId)
    }

    function moduleTitle(moduleItem) {
        var name = String(moduleItem && moduleItem.name ? moduleItem.name : "")
        var version = String(moduleItem && moduleItem.version ? moduleItem.version : "")
        if (version.length > 0) {
            return name + " (" + version + ")"
        }
        return name
    }

    readonly property bool hasNodeModules: !!dashboardBridge && !!dashboardBridge.nodeProjectModulesHasNodeModules
    readonly property bool isBusy: !!dashboardBridge && !!dashboardBridge.nodeProjectModulesBusy
    readonly property bool isLoaded: !!dashboardBridge && !!dashboardBridge.nodeProjectModulesLoaded
    readonly property string activeProjectId: String(pageRoot && pageRoot.editingNodeProjectId ? pageRoot.editingNodeProjectId : "")
    readonly property string loadedProjectId: String(dashboardBridge ? dashboardBridge.nodeProjectModulesProjectId : "")
    readonly property bool projectStateMatches: activeProjectId.length > 0 && loadedProjectId === activeProjectId
    readonly property bool showLoadingState: !projectStateMatches || root.isBusy || !root.isLoaded

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"

                Column {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        visible: root.hasNodeModules
                        width: parent.width
                        height: 24
                        color: Theme.surfaceAlt

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 0

                            Text {
                                width: 280
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Name"
                                color: Theme.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            Rectangle {
                                width: 1
                                height: 28
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.border
                            }

                            Text {
                                width: parent.width - 310
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                text: Strings.t("description")
                                color: Theme.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                        }
                    }

                    Rectangle {
                        visible: root.hasNodeModules
                        width: parent.width
                        height: 1
                        color: Theme.border
                    }

                    Components.AppScrollArea {
                        visible: true
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumHeight: 520
                        width: parent.width
                        height: Math.min(520, Math.max(0, parent.height - (root.hasNodeModules ? 32 : 0)))
                        clipContent: true

                        Column {
                            width: parent.width
                            spacing: 0

                            Item {
                                visible: root.showLoadingState
                                width: parent.width
                                height: visible ? 140 : 0

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 10

                                    BusyIndicator {
                                        running: true
                                        width: 28
                                        height: 28
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Text {
                                        text: String(dashboardBridge ? dashboardBridge.nodeProjectModulesMessage || "Loading modules..." : "Loading modules...")
                                        color: Theme.muted
                                        font.pixelSize: 13
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            Item {
                                visible: root.projectStateMatches && root.isLoaded && !root.isBusy && !root.hasNodeModules
                                width: parent.width
                                height: visible ? 220 : 0

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 12

                                    Text {
                                        width: 420
                                        text: "Dependencies are not installed for this project."
                                        color: Theme.muted
                                        font.pixelSize: 14
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            Item {
                                visible: root.projectStateMatches && root.isLoaded && !root.isBusy && root.hasNodeModules && dashboardBridge && dashboardBridge.nodeProjectModulesItems.length === 0
                                width: parent.width
                                height: visible ? 100 : 0

                                Text {
                                    anchors.centerIn: parent
                                    text: String(dashboardBridge ? dashboardBridge.nodeProjectModulesMessage || "No modules found." : "No modules found.")
                                    color: Theme.muted
                                    font.pixelSize: 13
                                }
                            }

                            Repeater {
                                model: dashboardBridge && root.projectStateMatches && root.isLoaded && root.hasNodeModules && !root.isBusy ? dashboardBridge.nodeProjectModulesItems : []

                                delegate: Rectangle {
                                    required property int index
                                    property var moduleItem: dashboardBridge.nodeProjectModulesItems[index]
                                    width: parent.width
                                    height: 28
                                    color: index % 2 === 0 ? Theme.surface : Theme.surfaceAlt

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 0

                                        Text {
                                            width: 280
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.moduleTitle(moduleItem)
                                            color: Theme.text
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width - 310
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 12
                                            text: String(moduleItem && moduleItem.description ? moduleItem.description : "")
                                            color: Theme.muted
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 1
                                        color: Theme.border
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        footerRight: Row {
            spacing: 8

            Components.AppButton {
                visible: root.hasNodeModules
                text: Strings.t("reload")
                enabled: !!dashboardBridge && !root.isBusy
                onClicked: root.reloadModules()
            }

            Components.AppButton {
                visible: !root.hasNodeModules
                text: "Install Dependencies"
                highlighted: true
                textColor: "white"
                enabled: !!dashboardBridge && !root.isBusy
                onClicked: root.installDependencies()
            }
        }
    }
}
