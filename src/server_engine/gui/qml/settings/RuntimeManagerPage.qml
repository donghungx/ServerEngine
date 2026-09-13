import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import "../components" as Components
import "../theme"
import "../i18n"

Item {
    required property var bridge
    required property var window
    required property var appSettingsWindow
    Layout.fillWidth: true
    Layout.fillHeight: true

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: Strings.t("install.or.remove.runtimes.here.select.the.active.web.server.version.in.web.server.settings.and.select.the.active.database.version.in.database.settings")
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                font.weight: Font.Medium
            }

            TabBar {
                id: runtimeManagerTabs
                Layout.fillWidth: true
                height: 28
                clip: true
                currentIndex: appSettingsWindow.runtimeManagerServiceIndex(appSettingsWindow.runtimeManagerService)
                enabled: !bridge.runtimeManagerBusy

                background: Rectangle { color: "transparent" }

                onCurrentIndexChanged: {
                    if (currentIndex < 0 || currentIndex >= appSettingsWindow.runtimeManagerServices.length) {
                        return
                    }
                    var nextService = appSettingsWindow.runtimeManagerServices[currentIndex].service
                    if (appSettingsWindow.runtimeManagerService !== nextService) {
                        appSettingsWindow.runtimeManagerService = nextService
                        appSettingsWindow.refreshRuntimeManager()
                    }
                }

                Repeater {
                    model: appSettingsWindow.runtimeManagerServices

                    delegate: TabButton {
                        id: runtimeManagerTabButton
                        required property int index
                        property var serviceTab: appSettingsWindow.runtimeManagerServices[index]
                        width: implicitWidth + 12
                        height: 28
                        text: serviceTab.label
                        enabled: runtimeManagerTabs.enabled

                        contentItem: Text {
                            text: runtimeManagerTabButton.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: runtimeManagerTabButton.checked
                                ? Theme.text
                                : Theme.muted
                            font.pixelSize: 12
                            font.weight: runtimeManagerTabButton.checked ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }

                        background: Rectangle {
                            anchors.fill: parent
                            anchors.margins: 0
                            radius: 8
                            color: runtimeManagerTabButton.checked
                                ? Theme.buttonNeutralHoverBackground
                                : (runtimeManagerTabButton.hovered ? Theme.buttonNeutralHoverBackground : "transparent")
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Column {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        width: parent.width
                        height: 32
                        color: "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 8
                            spacing: 10

                            Text { width: 170; anchors.verticalCenter: parent.verticalCenter; text: Strings.t("runtime"); color: Theme.muted; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: Strings.t("version"); color: Theme.muted; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { width: 120; anchors.verticalCenter: parent.verticalCenter; text: Strings.t("platform"); color: Theme.muted; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text {
                                width: 90
                                visible: appSettingsWindow.runtimeManagerService === "redis"
                                    || appSettingsWindow.runtimeManagerService === "memcached"
                                    || appSettingsWindow.runtimeManagerService === "mailpit"
                                    || appSettingsWindow.runtimeManagerService === "mongodb"
                                    || appSettingsWindow.runtimeManagerService === "postgresql"
                                anchors.verticalCenter: parent.verticalCenter
                                text: Strings.t("status")
                                color: Theme.muted
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Item {
                                width: Math.max(0, parent.width - (170 + 90 + 120 + (appSettingsWindow.runtimeManagerService === "redis"
                                    || appSettingsWindow.runtimeManagerService === "memcached"
                                    || appSettingsWindow.runtimeManagerService === "mailpit"
                                    || appSettingsWindow.runtimeManagerService === "mongodb"
                                    || appSettingsWindow.runtimeManagerService === "postgresql" ? 90 : 0) - 1 + 5 * 10 + 160))
                                height: 1
                            }
                            Text {
                                width: 160
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: "Value"
                                color: Theme.muted
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Components.AppScrollArea {
                        width: parent.width
                        height: parent.height - 34
                        clipContent: true
                        viewportMargins: 0
                        Column {
                            width: parent.width
                            spacing: 6

                            Text {
                                visible: appSettingsWindow.runtimeManagerModel.length === 0
                                text: bridge.runtimeManagerBusy ? "Loading..." : "No local runtime detected for this service."
                                color: Theme.muted
                                font.pixelSize: 13
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                padding: 30
                            }

                            Repeater {
                                model: appSettingsWindow.runtimeManagerModel

                                delegate: Rectangle {
                                    required property int index
                                    property var runtimeItem: appSettingsWindow.runtimeManagerModel[index]
                                    property string runtimeServiceId: String(runtimeItem.service || appSettingsWindow.runtimeManagerService)
                                    property bool protectSingleRuntimeRemoval: runtimeServiceId === "php"
                                        || runtimeServiceId === "phpmyadmin"
                                        || runtimeServiceId === "apache"
                                        || runtimeServiceId === "nginx"
                                        || runtimeServiceId === "mysql"
                                        || runtimeServiceId === "redis"
                                        || runtimeServiceId === "memcached"
                                        || runtimeServiceId === "mailpit"
                                    property bool allowActivateAction: runtimeServiceId === "redis"
                                        || runtimeServiceId === "memcached"
                                        || runtimeServiceId === "mailpit"
                                        || runtimeServiceId === "mongodb"
                                        || runtimeServiceId === "postgresql"
                                    width: parent.width
                                    height: 58
                                    radius: Theme.radius
                                    color: Theme.surfaceAlt
                                    border.color: Theme.border
                                    border.width: 1

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Column {
                                            width: 170 - 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            Text {
                                                text: String(runtimeItem.label || "")
                                                color: Theme.text
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                            Text {
                                                text: String(runtimeItem.home || "")
                                                color: Theme.muted
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }

                                        Text {
                                            width: 90
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(runtimeItem.version || "")
                                            color: Theme.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: 120 - 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(runtimeItem.platform || "") + " / " + String(runtimeItem.arch || "")
                                            color: Theme.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: 90
                                            visible: allowActivateAction
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(runtimeItem.status || "")
                                            color: String(runtimeItem.status || "") === "Active" ? "#4aa94b" : Theme.text
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        Item {
                                            width: Math.max(0, parent.width - (170 + 90 + 120 + (allowActivateAction ? 90 : 0) - 1 + 5 * 10 + 160))
                                            height: 1
                                        }

                                        Row {
                                            width: 160 + 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6
                                            layoutDirection: Qt.RightToLeft

                                            Components.AppButton {
                                                text: Strings.t("remove")
                                                visible: !!runtimeItem.canRemove
                                                    && !(
                                                        protectSingleRuntimeRemoval
                                                        && appSettingsWindow.runtimeManagerModel.length <= 1
                                                    )
                                                enabled: visible && !bridge.runtimeManagerBusy
                                                onClicked: {
                                                    window.runtimeRemoveService = runtimeServiceId
                                                    window.runtimeRemoveTarget = String(runtimeItem.id || "")
                                                    window.runtimeRemoveLabel = String(runtimeItem.label || runtimeItem.id || "")
                                                    window.runtimeRemoveServiceRunning = bridge.runtimeServiceRunning(runtimeServiceId)
                                                    window.runtimeRemoveConfirmOpen = true
                                                }
                                            }

                                            Components.AppButton {
                                                visible: allowActivateAction
                                                text: String(runtimeItem.status || "") === "Active"
                                                    ? "Active"
                                                    : (bridge.runtimeManagerBusy ? "Working..." : "Activate")
                                                enabled: visible
                                                    && !!runtimeItem.downloaded
                                                    && !!runtimeItem.canActivate
                                                    && !bridge.runtimeManagerBusy
                                                onClicked: {
                                                    window.runtimeSwitchService = runtimeServiceId
                                                    window.runtimeSwitchTarget = String(runtimeItem.id || "")
                                                    window.runtimeSwitchLabel = String(runtimeItem.label || runtimeItem.id || "")
                                                    window.runtimeSwitchServiceRunning = bridge.runtimeServiceRunning(runtimeServiceId)
                                                    window.runtimeSwitchConfirmOpen = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        footerLeft: Text {
            text: appSettingsWindow.scopedAppSettingsMessage
            color: bridge.appSettingsError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
            width: parent.width
            visible: text.length > 0
        }

        footerRight: Row {
            spacing: 10

            Components.AppButton {
                text: Strings.t("install.runtime")
                enabled: !bridge.runtimeManagerBusy
                onClicked: appSettingsWindow.runtimeInstallOpen = true
            }
        }
    }
}
