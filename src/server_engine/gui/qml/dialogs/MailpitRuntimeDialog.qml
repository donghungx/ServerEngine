import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import "../components" as Components
import "mailpit_runtime_sections" as MailpitSections
import "../theme"
import "../i18n"

Window {
    required property var pageRoot
    required property var dashboardBridge

    id: runtimeWindow
    visible: pageRoot.runtimePopupOpen
    width: 720
    height: 560
    minimumWidth: width
    maximumWidth: width
    minimumHeight: 420
    maximumHeight: 820
    title: Strings.t("mailpit.runtime")
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
            nextHeight = 420
            break
        case "port":
            nextHeight = 520
            break
        case "switch.version":
            nextHeight = 520
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
        id: mailpitRuntimeRefreshTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (!runtimeWindow.visible) {
                return
            }
            dashboardBridge.refreshMailpitRuntime()
        }
    }

    onVisibleChanged: {
        if (visible) {
            pageRoot.refreshMailpitDraft()
            mailpitRuntimeRefreshTimer.restart()
            Qt.callLater(function() {
                applyRuntimeWindowHeight(pageRoot.runtimePopupSection)
            })
        } else {
            mailpitRuntimeRefreshTimer.stop()
            pageRoot.runtimePopupOpen = false
        }
    }

    Components.PageWindowFrame {
        moveWindow: runtimeWindow
        bodyMargins: 16

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
                            label: runtimeTopTabItem.navItem.label
                            iconSource: "../icons/lucide/" + pageRoot.runtimeSectionIcon(runtimeTopTabItem.navItem.id) + ".svg"
                            onClicked: {
                                pageRoot.runtimePopupSection = runtimeTopTabItem.navItem.id
                                runtimeWindow.applyRuntimeWindowHeight(runtimeTopTabItem.navItem.id)
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent

            Loader {
                id: sectionLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: pageRoot.runtimePopupSection === "switch.version"
                    ? switchVersionSection
                    : pageRoot.runtimePopupSection === "general"
                    ? generalSection
                    : pageRoot.runtimePopupSection === "port"
                        ? portSection
                    : pageRoot.runtimePopupSection === "logs"
                        ? logsSection
                        : serviceSection
                onLoaded: {
                    Qt.callLater(function() {
                        runtimeWindow.applyRuntimeWindowHeight(pageRoot.runtimePopupSection)
                    })
                }
            }
        }
    }

Component {
    id: generalSection
    Item {
        anchors.fill: parent
        property var sectionPageRoot: pageRoot
        property var sectionDashboardBridge: dashboardBridge
        property var sectionRuntimeWindow: runtimeWindow
        MailpitSections.GeneralSection {
            anchors.fill: parent
            pageRoot: parent.sectionPageRoot
            dashboardBridge: parent.sectionDashboardBridge
            runtimeWindow: parent.sectionRuntimeWindow
        }
    }
}

Component {
    id: switchVersionSection
    Item {
        anchors.fill: parent
        property var sectionPageRoot: pageRoot
        property var sectionDashboardBridge: dashboardBridge
        property var sectionRuntimeWindow: runtimeWindow
        MailpitSections.SwitchVersionSection {
            anchors.fill: parent
            pageRoot: parent.sectionPageRoot
            dashboardBridge: parent.sectionDashboardBridge
            runtimeWindow: parent.sectionRuntimeWindow
        }
    }
}

Component {
    id: serviceSection
    Item {
        anchors.fill: parent
        property var sectionPageRoot: pageRoot
        property var sectionDashboardBridge: dashboardBridge
        property var sectionRuntimeWindow: runtimeWindow
        MailpitSections.ServiceSection {
            anchors.fill: parent
            pageRoot: parent.sectionPageRoot
            dashboardBridge: parent.sectionDashboardBridge
            runtimeWindow: parent.sectionRuntimeWindow
        }
    }
}

Component {
    id: portSection
    Item {
        anchors.fill: parent
        property var sectionPageRoot: pageRoot
        property var sectionDashboardBridge: dashboardBridge
        property var sectionRuntimeWindow: runtimeWindow
        MailpitSections.PortSection {
            anchors.fill: parent
            pageRoot: parent.sectionPageRoot
            dashboardBridge: parent.sectionDashboardBridge
            runtimeWindow: parent.sectionRuntimeWindow
        }
    }
}

Component {
    id: logsSection
    Item {
        anchors.fill: parent
        property var sectionPageRoot: pageRoot
        property var sectionDashboardBridge: dashboardBridge
        property var sectionRuntimeWindow: runtimeWindow
        MailpitSections.LogsSection {
            anchors.fill: parent
            pageRoot: parent.sectionPageRoot
            dashboardBridge: parent.sectionDashboardBridge
            runtimeWindow: parent.sectionRuntimeWindow
        }
    }
}
}
