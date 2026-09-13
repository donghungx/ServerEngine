import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../components" as Components
import "../../../theme"
import "../../../i18n"

Window {
    id: postgresqlRuntimeWindow
    property var root: ({})
    property var dashboardBridge: ({})

    function bridge() {
        return dashboardBridge || ({})
    }

    function postgresqlRuntimeSectionSource(sectionId) {
        switch (sectionId) {
        case "settings":
            return "../../../pages/postgresql_runtime_sections/SettingsSection.qml"
        case "service":
            return "../../../pages/postgresql_runtime_sections/ServiceSection.qml"
        case "configuration":
            return "../../../pages/postgresql_runtime_sections/ConfigFileSection.qml"
        case "data.directory":
            return "../../../pages/postgresql_runtime_sections/StorageLocationSection.qml"
        case "port":
            return "../../../pages/postgresql_runtime_sections/PortSection.qml"
        case "current.status":
            return "../../../pages/postgresql_runtime_sections/CurrentStatusSection.qml"
        case "error.log":
            return "../../../pages/postgresql_runtime_sections/ErrorLogSection.qml"
        case "slow.log":
            return "../../../pages/postgresql_runtime_sections/SlowLogSection.qml"
        default:
            return "../../../pages/postgresql_runtime_sections/PlaceholderSection.qml"
        }
    }

    visible: root.runtimePopupOpen
    width: 720
    height: 620
    minimumWidth: width
    maximumWidth: width
    minimumHeight: 400
    maximumHeight: 820
    title: String(bridge().activePostgresqlRuntimeLabel || "PostgreSQL") + " Runtime"
    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: root && root.Window ? root.Window.window : null
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        function applyRuntimeWindowHeight(sectionId) {
            var nextHeight = 620
            switch (String(sectionId || "")) {
            case "service":
                nextHeight = 400
                break
            case "configuration":
                nextHeight = 560
                break
            case "data.directory":
                nextHeight = 500
                break
            case "port":
                nextHeight = 500
                break
            case "error.log":
                nextHeight = 640
                break
            case "settings":
            default:
                nextHeight = 620
                break
            }
            nextHeight = Math.max(minimumHeight, Math.min(maximumHeight, nextHeight))
            if (height !== nextHeight) {
                height = nextHeight
            }
        }

        onVisibleChanged: {
            if (visible) {
                Qt.callLater(function() {
                    bridge().refreshPostgresqlRuntime && bridge().refreshPostgresqlRuntime()
                    root.refreshPostgresqlConfigDraft()
                    root.refreshPostgresqlGeneralDraft()
                    applyRuntimeWindowHeight(root.postgresqlRuntimePopupSection)
                })
            } else {
                root.runtimePopupOpen = false
            }
        }

        Components.PageWindowFrame {
            moveWindow: postgresqlRuntimeWindow
            bodyMargins: 20

            headerContent: Item {
                anchors.fill: parent

                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 8
                    text: root.postgresqlRuntimeSectionLabel(root.postgresqlRuntimePopupSection)
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
                            model: root.postgresqlRuntimePopupSections

                            delegate: Components.TopIconTab {
                                id: runtimeTopTabItem
                                required property int index
                                property var navItem: root.postgresqlRuntimePopupSections[index]
                                selected: root.postgresqlRuntimePopupSection === navItem.id
                                label: Strings.t(runtimeTopTabItem.navItem.id)
                                iconSource: "../icons/lucide/" + root.postgresqlRuntimeSectionIcon(runtimeTopTabItem.navItem.id) + ".svg"
                                onClicked: {
                                    root.postgresqlRuntimePopupSection = runtimeTopTabItem.navItem.id
                                    if (runtimeTopTabItem.navItem.id === "settings") {
                                        root.refreshPostgresqlGeneralDraft()
                                    }
                                    if (runtimeTopTabItem.navItem.id === "configuration") {
                                        root.refreshPostgresqlConfigDraft()
                                    }
                                    postgresqlRuntimeWindow.applyRuntimeWindowHeight(runtimeTopTabItem.navItem.id)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent

                Loader {
                    id: postgresqlRuntimeSectionLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    source: postgresqlRuntimeSectionSource(root.postgresqlRuntimePopupSection)
                    onLoaded: {
                        if (item) {
                            item.pageRoot = root
                            item.dashboardBridge = dashboardBridge
                            item.runtimeWindow = postgresqlRuntimeWindow
                        }
                        Qt.callLater(function() {
                            postgresqlRuntimeWindow.applyRuntimeWindowHeight(root.postgresqlRuntimePopupSection)
                        })
                    }
                }
            }
        }
    }
