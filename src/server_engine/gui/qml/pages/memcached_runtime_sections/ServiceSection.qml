import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"
import "../../components" as Components
import "../../i18n"

Item {
    property var pageRoot
    property var dashboardBridge
    property var runtimeWindow

    Components.SettingsTabFrame {
        anchors.fill: parent
        color: "transparent"
        contentMargins: 0
        contentSpacing: 10
        footerRightMargin: 0
        footerBottomMargin: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: String(dashboardBridge.activeMemcachedServiceState || "").toLowerCase() === "running" ? Theme.success : Theme.danger
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Server Status"; color: Theme.muted; font.pixelSize: 11 }
                    Text { text: String(dashboardBridge.activeMemcachedServiceState || "Stopped"); color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.65 }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 18
                rowSpacing: 8
                Text { text: "Runtime"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeMemcachedRuntimeLabel || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Home"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeMemcachedRuntimeHome || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Data dir"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeMemcachedDataDir || "-"); color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                Text { text: "Port"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: String(dashboardBridge.activeMemcachedPort || "-"); color: Theme.muted; font.pixelSize: 13 }
                Text { text: "Protocol"; color: Theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                Text { text: "Memcached TCP"; color: Theme.muted; font.pixelSize: 13 }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footerLeft: Text {
            text: dashboardBridge.memcachedRuntimeMessage
            color: dashboardBridge.memcachedRuntimeError ? "#bb4d4d" : "#4aa94b"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            width: parent.width
        }

        footerRight: Row {
            spacing: 8
            Components.AppButton {
                visible: !pageRoot.cacheRunning
                text: dashboardBridge.memcachedActionBusy ? "Starting..." : "Start"
                highlighted: true
                textColor: "white"
                enabled: !dashboardBridge.memcachedActionBusy
                onClicked: dashboardBridge.startMemcachedRuntime()
            }
            Components.AppButton {
                visible: pageRoot.cacheRunning
                text: dashboardBridge.memcachedActionBusy ? "Stopping..." : "Stop"
                enabled: !dashboardBridge.memcachedActionBusy
                onClicked: dashboardBridge.stopMemcachedRuntime()
            }
            Components.AppButton {
                text: Strings.t("restart")
                enabled: !dashboardBridge.memcachedActionBusy
                onClicked: dashboardBridge.restartMemcachedRuntime()
            }
            Components.AppButton {
                text: Strings.t("refresh")
                onClicked: dashboardBridge.refreshMemcachedRuntime()
            }
        }
    }
}
