import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components" as Components
import "../../theme"
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    function saveTestedDraft() {
        var ok = dashboardBridge.saveActiveApacheConfigContent(pageRoot.apacheConfigDraft)
        pageRoot.apacheConfigFeedback = dashboardBridge.apacheRuntimeMessage
        if (!ok) {
            return
        }
        if (runtimeWindow && runtimeWindow.refreshApacheDrafts) {
            runtimeWindow.refreshApacheDrafts()
        }
        if (runtimeWindow && runtimeWindow.webRunning) {
            dashboardBridge.restartWebServerRuntime()
        }
    }

    Connections {
        target: mainWindow()
        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "apache.save_config") {
                root.saveTestedDraft()
            }
        }
    }

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("configuration")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: "Edit the active Apache main configuration file before startup."
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: String(dashboardBridge.activeApacheConfigPath || "")
                color: Theme.text
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }

            Components.AppScrollEditor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: pageRoot.apacheConfigDraft
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                fontPixelSize: 12
                fontFamily: "Menlo"
                textColor: Theme.text
                readOnly: false
                onTextChanged: {
                    if (pageRoot) {
                        pageRoot.apacheConfigDraft = text
                    }
                }
            }
        }

        footerLeft: Text {
            text: pageRoot.apacheConfigFeedback
            color: dashboardBridge.apacheRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Item {
                width: refreshButton.width
                height: 30

                Components.QuickActionButton {
                    id: refreshButton
                    anchors.centerIn: parent
                    iconSource: "../icons/lucide/rotate-cw.svg"
                    tooltip: Strings.t("refresh")
                    onClicked: {
                        if (runtimeWindow && runtimeWindow.refreshApacheDrafts) {
                            runtimeWindow.refreshApacheDrafts()
                        }
                    }
                }
            }
            Components.AppButton {
                text: Strings.t("reveal.in.finder")
                onClicked: dashboardBridge.revealInFinder(String(dashboardBridge.activeApacheConfigPath || ""))
            }
            Components.AppButton {
                text: Strings.t("restore.original")
                onClicked: {
                    var ok = dashboardBridge.restoreActiveApacheConfigOriginal()
                    pageRoot.apacheConfigFeedback = dashboardBridge.apacheRuntimeMessage
                    if (ok) {
                        if (runtimeWindow && runtimeWindow.refreshApacheDrafts) {
                            runtimeWindow.refreshApacheDrafts()
                        }
                    }
                }
            }
            Components.AppButton {
                text: Strings.t("test.config")
                onClicked: dashboardBridge.testApacheConfig()
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var valid = dashboardBridge.testActiveApacheConfigDraft(pageRoot.apacheConfigDraft)
                    pageRoot.apacheConfigFeedback = dashboardBridge.apacheRuntimeMessage
                    if (!valid) {
                        return
                    }
                    var appWindow = root.mainWindow()
                    if (appWindow && appWindow.openGlobalConfirm) {
                        appWindow.openGlobalConfirm(
                            "Save Apache configuration",
                            runtimeWindow && runtimeWindow.webRunning
                                ? "The configuration passed Apache's test. Save it and restart Apache now?"
                                : "The configuration passed Apache's test. Save it now?",
                            "apache.save_config",
                            {},
                            "Save",
                            Strings.t("cancel"),
                            runtimeWindow
                        )
                    } else {
                        root.saveTestedDraft()
                    }
                }
            }
        }
    }
}
