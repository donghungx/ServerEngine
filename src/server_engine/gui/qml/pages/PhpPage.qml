import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Components.ShellCard {
    id: root
    color: "transparent"
    required property var dashboardBridge
    signal installMoreSelected()
    signal openPhpSettingsRequested()
    border.width: 0
    property bool phpDetailsOpen: false
    property var selectedPhpRuntime: ({})
    property string selectedPhpSection: "configuration"
    property var phpSections: [
        { id: "configuration", label: Strings.t("configuration") },
        { id: "php.ini", label: Strings.t("php.ini") },
        { id: "extensions", label: Strings.t("extensions") },
        { id: "functions", label: Strings.t("functions") },
        { id: "logs", label: Strings.t("logs") },
        { id: "phpinfo", label: Strings.t("phpinfo") }
    ]
    readonly property string phpFilterText: phpFilterField ? String(phpFilterField.text || "").trim().toLowerCase() : ""
    readonly property var filteredPhpRuntimeItems: {
        var items = dashboardBridge ? (dashboardBridge.phpRuntimeItems || []) : []
        if (phpFilterText.length === 0) {
            return items
        }
        return items.filter(function(item) {
            var values = [
                String(item.label || ""),
                String(item.version || ""),
                String(item.path || ""),
                String(item.home || "")
            ]
            return values.join(" ").toLowerCase().indexOf(phpFilterText) !== -1
        })
    }

    function phpSectionSource(sectionLabel) {
        switch (sectionLabel) {
        case "configuration":
            return "php_details/ConfigurationSection.qml"
        case "php.ini":
            return "php_details/ConfigurationFileSection.qml"
        case "extensions":
            return "php_details/InstallExtensionsSection.qml"
        case "functions":
            return "php_details/DisabledFunctionsSection.qml"
        case "logs":
            return "php_details/LogsSection.qml"
        case "phpinfo":
            return "php_details/PhpInfoSection.qml"
        default:
            return "php_details/ConfigurationSection.qml"
        }
    }

    function phpSectionDescription(sectionLabel) {
        switch (sectionLabel) {
        case "extensions":
            return Strings.t("extension.installation.and.activation.controls.will.live.here")
        case "php.ini":
            return Strings.t("direct.php.ini.file.editing.and.path.details.will.live.here")
        case "functions":
            return Strings.t("function.blacklist.management.will.live.here")
        case "optimization":
            return Strings.t("opcode.cache.and.runtime.optimization.settings.will.live.here")
        case "load.average":
            return Strings.t("runtime.load.metrics.and.health.details.will.live.here")
        case "session":
            return Strings.t("session.storage.and.lifetime.settings.will.live.here")
        case "logs":
            return Strings.t("php.runtime.logs.and.error.output.will.live.here")
        case "slow.log":
            return Strings.t("slow.request.log.controls.will.live.here")
        case "phpinfo":
            return Strings.t("phpinfo.output.and.environment.details.will.live.here")
        default:
            return Strings.t("this.section.is.ready.for.content")
        }
    }

    function phpSectionIcon(sectionLabel) {
        switch (sectionLabel) {
        case "configuration":
            return "settings"
        case "php.ini":
            return "file-code-corner"
        case "extensions":
            return "blocks"
        case "functions":
            return "square-function"
        case "optimization":
            return "server"
        case "load.average":
            return "panel-top"
        case "session":
            return "cable"
        case "logs":
            return "file-text"
        case "slow.log":
            return "file-text"
        case "phpinfo":
            return "badge-info"
        default:
            return "settings"
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 64
        anchors.rightMargin: 16
        spacing: 14

        RowLayout {
            width: parent.width
            spacing: 8

            Components.AppButton {
                text: Strings.t("install.more")
                iconSource: "icons/lucide/package.svg"
                onClicked: root.installMoreSelected()
            }

            Text {
                text: dashboardBridge.phpRuntimeItems.length + " runtime(s) detected"
                color: Theme.muted
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            Components.AppTextField {
                id: phpFilterField
                Layout.preferredWidth: 300
                placeholderText: Strings.t("php.version.or.path")

                selectByMouse: true
            }

            Components.QuickActionButton {
                iconSource: "../icons/lucide/settings.svg"
                tooltip: Strings.t("php.settings")
                onClicked: root.openPhpSettingsRequested()
            }
        }

        Rectangle {
            width: parent.width
            height: 40
            radius: Theme.radius
            color: Theme.surfaceAlt
            border.color: Theme.border
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 0

                Components.HeaderCell { label: Strings.t("php.version"); cellWidth: 312 }
                Components.HeaderCell { label: Strings.t("status"); cellWidth: 140 }
            }
        }

        Rectangle {
            width: parent.width
            height: parent.height - 120
            radius: Theme.radius
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            clip: true

            Components.AppScrollArea {
                anchors.fill: parent
                clipContent: true

                ListView {
                    width: parent.width
                    height: contentHeight
                    implicitHeight: contentHeight
                    model: root.filteredPhpRuntimeItems
                    visible: count > 0
                    interactive: false
                    clip: true

                    delegate: Column {
                        required property int index
                        width: ListView.view.width
                        property var phpRuntimeItem: root.filteredPhpRuntimeItems[index]

                        Components.PhpRuntimeRow {
                            width: parent.width
                            height: 62
                            rowData: parent.phpRuntimeItem
                            dashboardBridge: root.dashboardBridge
                            onPhpIniSelected: {
                                root.selectedPhpRuntime = parent.phpRuntimeItem
                                root.selectedPhpSection = "php.ini"
                                root.phpDetailsOpen = true
                            }
                            onSettingsSelected: {
                                root.selectedPhpRuntime = parent.phpRuntimeItem
                                root.selectedPhpSection = "configuration"
                                root.phpDetailsOpen = true
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.border
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                visible: root.filteredPhpRuntimeItems.length === 0
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.phpFilterText.length > 0 ? Strings.t("no.matching.php.runtimes") : Strings.t("no.php.runtimes.detected")
                    color: Theme.text
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.phpFilterText.length > 0
                        ? Strings.t("try.a.different.php.version.or.path.keyword")
                        : Strings.t("this.page.only.shows.php.versions.already.available.on.the.system")
                    color: Theme.muted
                    font.pixelSize: 14
                }
            }
        }
    }

    Window {
        id: phpDetailsWindow
        width: 720
        height: 480
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        visible: root.phpDetailsOpen
        title: selectedPhpRuntime.label ? selectedPhpRuntime.label + " " + Strings.t("manage") : Strings.t("php.settings")
        modality: Qt.ApplicationModal
        transientParent: root.Window.window
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
        color: Theme.surface

        onClosing: function(closeEvent) {
            root.phpDetailsOpen = false
        }

        Components.PageWindowFrame {
            moveWindow: phpDetailsWindow
            bodyMargins: 20

            headerContent: Item {
                anchors.fill: parent

                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 8
                    text: Strings.t(root.selectedPhpSection)
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Item {
                    anchors.fill: parent
                    anchors.topMargin: 28
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.bottomMargin: 6
                    clip: true

                    Row {
                        height: 58
                        spacing: 6

                        Repeater {
                            model: root.phpSections

                            delegate: Components.TopIconTab {
                                id: phpTopTabItem
                                required property int index
                                property var navItem: root.phpSections[index]
                                selected: root.selectedPhpSection === navItem.id
                                label: phpTopTabItem.navItem.label
                                iconSource: "../icons/lucide/" + root.phpSectionIcon(phpTopTabItem.navItem.id) + ".svg"
                                onClicked: root.selectedPhpSection = phpTopTabItem.navItem.id
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Loader {
                    id: phpSectionLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    source: root.phpSectionSource(root.selectedPhpSection)
                    property var runtimeData: root.selectedPhpRuntime

                    function syncLoadedItem() {
                        if (!item) {
                            return
                        }
                        try {
                            item.phpRuntime = runtimeData
                        } catch (error) {
                        }
                        try {
                            item.dashboardBridge = root.dashboardBridge
                        } catch (error2) {
                        }
                        try {
                            item.titleText = root.selectedPhpSection
                        } catch (error3) {
                        }
                        try {
                            item.bodyText = root.phpSectionDescription(root.selectedPhpSection)
                        } catch (error4) {
                        }
                        if (item.loadIniContent) {
                            item.loadIniContent()
                        } else if (item.loadSettings) {
                            item.loadSettings()
                        } else if (item.loadPhpInfo) {
                            item.loadPhpInfo()
                        } else if (item.loadLogs) {
                            item.loadLogs()
                        } else if (item.loadFunctions) {
                            item.loadFunctions()
                        }
                    }

                    onRuntimeDataChanged: syncLoadedItem()
                    onLoaded: {
                        syncLoadedItem()
                    }
                }
            }
        }
    }
}
