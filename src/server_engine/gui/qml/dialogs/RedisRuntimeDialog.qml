import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    required property var pageRoot
    required property var dashboardBridge

    id: redisRuntimeWindow
    visible: pageRoot.runtimePopupOpen
    width: 720
    height: 560
    minimumWidth: width
    maximumWidth: width
    minimumHeight: 400
    maximumHeight: 820
    title: dashboardBridge ? dashboardBridge.activeRedisRuntimeLabel + " Runtime" : "Redis Runtime"
    color: Theme.surface
    modality: Qt.ApplicationModal
    transientParent: pageRoot.Window.window
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Behavior on height {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    function applyRuntimeWindowHeight(sectionId) {
        var nextHeight = 560
        switch (String(sectionId || "")) {
        case "service":
            nextHeight = 400
            break
        case "switch.version":
            nextHeight = 520
            break
        case "configuration":
            nextHeight = 560
            break
        case "port":
            nextHeight = 500
            break
        case "logs":
            nextHeight = 640
            break
        case "general":
        default:
            nextHeight = 620
            break
        }
        nextHeight = Math.max(minimumHeight, Math.min(maximumHeight, nextHeight))
        if (height !== nextHeight) {
            height = nextHeight
        }
    }

    Timer {
        id: redisRuntimeRefreshTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (!redisRuntimeWindow.visible) {
                return
            }
            if (dashboardBridge && dashboardBridge.refreshRedisRuntime) {
                dashboardBridge.refreshRedisRuntime()
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            pageRoot.runtimePopupSection = "general"
            pageRoot.refreshRedisGeneralDraft()
            pageRoot.refreshRedisConfigDraft()
            redisRuntimeRefreshTimer.restart()
            Qt.callLater(function() {
                applyRuntimeWindowHeight(pageRoot.runtimePopupSection)
            })
        } else {
            redisRuntimeRefreshTimer.stop()
            pageRoot.runtimePopupOpen = false
        }
    }

    function reloadSection() {
        if (!redisRuntimeSectionLoader) {
            return
        }
        var sourcePath = pageRoot.redisRuntimeSectionSource(pageRoot.runtimePopupSection)
        redisRuntimeSectionLoader.setSource(
            sourcePath,
            {
                pageRoot: redisRuntimeWindow.pageRoot,
                dashboardBridge: redisRuntimeWindow.dashboardBridge,
                runtimeWindow: redisRuntimeWindow
            }
        )
    }

    Connections {
        target: pageRoot
        function onRuntimePopupSectionChanged() {
            reloadSection()
        }
    }

    Component.onCompleted: reloadSection()

    Components.PageWindowFrame {
        moveWindow: redisRuntimeWindow
        bodyMargins: 20

        headerContent: Item {
            anchors.fill: parent

            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                text: Strings.t(pageRoot.runtimePopupSection)
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
                        model: pageRoot.runtimePopupSections

                        delegate: Components.TopIconTab {
                            id: runtimeTopTabItem
                            required property int index
                            property var navItem: pageRoot.runtimePopupSections[index]
                            selected: pageRoot.runtimePopupSection === navItem.id
                            label: Strings.t(runtimeTopTabItem.navItem.id)
                            iconSource: "../icons/lucide/" + pageRoot.runtimeSectionIcon(runtimeTopTabItem.navItem.id) + ".svg"
                            onClicked: {
                                pageRoot.runtimePopupSection = runtimeTopTabItem.navItem.id
                                if (runtimeTopTabItem.navItem.id === "general") {
                                    pageRoot.refreshRedisGeneralDraft()
                                }
                                if (runtimeTopTabItem.navItem.id === "configuration") {
                                    pageRoot.refreshRedisConfigDraft()
                                }
                                redisRuntimeWindow.applyRuntimeWindowHeight(runtimeTopTabItem.navItem.id)
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent

            Loader {
                id: redisRuntimeSectionLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                onLoaded: {
                    Qt.callLater(function() {
                        redisRuntimeWindow.applyRuntimeWindowHeight(pageRoot.runtimePopupSection)
                    })
                }
            }
        }
    }
}
