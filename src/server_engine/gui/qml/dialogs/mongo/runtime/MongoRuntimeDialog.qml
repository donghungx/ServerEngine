import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../components" as Components
import "../../../theme"
import "../../../i18n"

Window {
    id: mongodbRuntimeWindow
    property var root: ({})
    property var dashboardBridge: ({})

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (root && root.dashboardBridge) {
            return root.dashboardBridge
        }
        return ({})
    }

    function mongodbRuntimeSectionSource(sectionId) {
        switch (sectionId) {
        case "settings":
            return "../../../pages/mongodb_runtime_sections/SettingsSection.qml"
        case "service":
            return "../../../pages/mongodb_runtime_sections/ServiceSection.qml"
        case "configuration":
            return "../../../pages/mongodb_runtime_sections/ConfigFileSection.qml"
        case "data.directory":
            return "../../../pages/mongodb_runtime_sections/StorageLocationSection.qml"
        case "port":
            return "../../../pages/mongodb_runtime_sections/PortSection.qml"
        case "current.status":
            return "../../../pages/mongodb_runtime_sections/CurrentStatusSection.qml"
        case "error.log":
            return "../../../pages/mongodb_runtime_sections/ErrorLogSection.qml"
        case "slow.log":
            return "../../../pages/mongodb_runtime_sections/SlowLogSection.qml"
        default:
            return "../../../pages/mongodb_runtime_sections/PlaceholderSection.qml"
        }
    }

        visible: root.runtimePopupOpen
        width: 720
        height: 620
        minimumWidth: width
        maximumWidth: width
        minimumHeight: 400
        maximumHeight: 820
        title: String(bridge().activeMongodbRuntimeLabel || "MongoDB") + " Runtime"
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
                root && root.refreshMongodbRuntimeInfo && root.refreshMongodbRuntimeInfo()
                bridge().refreshMongodbRuntime && bridge().refreshMongodbRuntime()
                root && root.refreshMongodbConfigDraft && root.refreshMongodbConfigDraft()
                root && root.refreshMongodbGeneralDraft && root.refreshMongodbGeneralDraft()
                Qt.callLater(function() {
                    applyRuntimeWindowHeight(root.mongodbRuntimePopupSection)
                })
            } else {
                root.runtimePopupOpen = false
            }
        }

        Components.PageWindowFrame {
            moveWindow: mongodbRuntimeWindow
            bodyMargins: 16

            headerContent: Item {
                anchors.fill: parent

                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 8
                    text: mongodbRuntimeSectionLabel(root.mongodbRuntimePopupSection)
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
                            model: root.mongodbRuntimePopupSections

                            delegate: Components.TopIconTab {
                                id: runtimeTopTabItem
                                required property int index
                                property var navItem: root.mongodbRuntimePopupSections[index]
                                selected: root.mongodbRuntimePopupSection === navItem.id
                                label: Strings.t(runtimeTopTabItem.navItem.id)
                                iconSource: "../icons/lucide/" + root.mongodbRuntimeSectionIcon(runtimeTopTabItem.navItem.id) + ".svg"
                                onClicked: {
                                    root.mongodbRuntimePopupSection = runtimeTopTabItem.navItem.id
                                    if (runtimeTopTabItem.navItem.id === "settings") {
                                        root && root.refreshMongodbGeneralDraft && root.refreshMongodbGeneralDraft()
                                    }
                                    if (runtimeTopTabItem.navItem.id === "configuration") {
                                        root && root.refreshMongodbConfigDraft && root.refreshMongodbConfigDraft()
                                    }
                                    mongodbRuntimeWindow.applyRuntimeWindowHeight(runtimeTopTabItem.navItem.id)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 20

                Loader {
                    id: mongodbRuntimeSectionLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    source: mongodbRuntimeSectionSource(root.mongodbRuntimePopupSection)
                    onLoaded: {
                        if (item) {
                            item.pageRoot = root
                            item.dashboardBridge = dashboardBridge
                            item.runtimeWindow = mongodbRuntimeWindow
                        }
                        Qt.callLater(function() {
                            mongodbRuntimeWindow.applyRuntimeWindowHeight(root.mongodbRuntimePopupSection)
                        })
                    }
                }
            }
        }
    }
