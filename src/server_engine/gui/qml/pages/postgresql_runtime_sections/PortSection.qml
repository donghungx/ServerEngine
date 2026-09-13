import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    id: root
    property var pageRoot: ({})
    property var dashboardBridge: ({})
    property var runtimeWindow
    property string portDraft: ""
    property string loadedPort: ""
    property string feedbackText: ""
    property bool feedbackError: false
    property bool restartConfirmOpen: false

    function loadPort() {
        var currentBridge = bridge()
        if (!currentBridge) {
            return
        }
        var current = String((currentBridge && currentBridge.activePostgresqlPort) || "")
        if (current.length === 0) {
            current = String((currentBridge && currentBridge.settingsPostgresqlPort) || "")
        }
        loadedPort = current
        portDraft = current
        portField.text = current
    }

    function bridge() {
        if (dashboardBridge) {
            return dashboardBridge
        }
        if (pageRoot && pageRoot.dashboardBridge) {
            return pageRoot.dashboardBridge
        }
        return ({})
    }

    function mainWindow() {
        return pageRoot && pageRoot.Window ? pageRoot.Window.window : null
    }

    Connections {
        target: mainWindow()

        function onGlobalConfirmAccepted(actionId, payload) {
            if (actionId === "postgresql.restart_after_port_save") {
                bridge().restartPostgresqlRuntime && bridge().restartPostgresqlRuntime()
            }
        }
    }

    Component.onCompleted: loadPort()
    onDashboardBridgeChanged: loadPort()

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: Strings.t("port")
                color: Theme.text
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: Strings.t("listen.port.details.for.the.active.postgresql.runtime")
                color: Theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 8

                Text {
                    text: Strings.t("postgresql.port")
                    color: Theme.muted
                    font.pixelSize: 12
                }

                Components.AppTextField {
                    id: portField
                    text: root.portDraft
                    inputMethodHints: Qt.ImhDigitsOnly
                    onTextChanged: root.portDraft = text
                }

                Text {
                    text: Strings.t("current.runtime.port")
                    color: Theme.muted
                    font.pixelSize: 12
                }

                Text {
                    text: String((bridge() && bridge().activePostgresqlPort) || "-")
                    color: Theme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: feedbackText
            color: feedbackError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            visible: text.length > 0
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                text: Strings.t("reload")
                onClicked: loadPort()
            }
            Components.AppButton {
                text: Strings.t("settings.appearance.save")
                highlighted: true
                textColor: "white"
                onClicked: {
                    var before = String(root.loadedPort)
                    var after = String(root.portDraft).trim()
                    var ok = bridge().updatePostgresqlRuntimePort ? bridge().updatePostgresqlRuntimePort(after) : false
                    feedbackText = String(bridge().postgresqlRuntimeMessage || "")
                    feedbackError = !ok
                    if (!ok) {
                        return
                    }
                    root.loadedPort = after
                    if (pageRoot.postgresqlRunning && before !== after) {
                        var appWindow = mainWindow()
                        if (appWindow && appWindow.openGlobalConfirm) {
                            appWindow.openGlobalConfirm(
                                "Restart PostgreSQL runtime",
                                "PostgreSQL runtime is running. Restart now to apply the new port?",
                                "postgresql.restart_after_port_save",
                                {},
                                Strings.t("restart"),
                                Strings.t("later"),
                                runtimeWindow
                            )
                        } else {
                            restartConfirmOpen = true
                        }
                    }
                }
            }
        }
    }

    Window {
        id: restartConfirmWindow
        visible: restartConfirmOpen
        width: 500
        height: 190
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: Strings.t("restart.postgresql.runtime")
        modality: Qt.ApplicationModal
        transientParent: runtimeWindow
        flags: Qt.Window
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        x: runtimeWindow ? runtimeWindow.x + Math.round((runtimeWindow.width - width) / 2) : 0
        y: runtimeWindow ? runtimeWindow.y + Math.round((runtimeWindow.height - height) / 2) : 0

        onVisibleChanged: {
            if (!visible) {
                restartConfirmOpen = false
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 16
                    spacing: 14

                Label {
                    Layout.fillWidth: true
                    text: Strings.t("postgresql.runtime.is.running.restart.now.to.apply.new.port")
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    Components.AppButton {
                        text: Strings.t("later")
                        onClicked: restartConfirmOpen = false
                    }

                    Components.AppButton {
                        text: Strings.t("restart")
                        highlighted: true
                        textColor: "white"
                        onClicked: {
                            restartConfirmOpen = false
                            bridge().restartPostgresqlRuntime && bridge().restartPostgresqlRuntime()
                        }
                    }
                }
            }
        }
    }
}


