import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: root
    required property var window
    required property var bridge
    required property var appSettingsWindow

    visible: window.runtimeInstallOpen
    width: 680
    height: 480
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("install.runtime")
    color: "transparent"
    modality: Qt.WindowModal
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.FramelessWindowHint
    transientParent: window

    readonly property string loadedLabel: "Loaded " + String(appSettingsWindow.runtimeServerModel.length || 0) + " server runtime(s)"
    readonly property var selectedRuntime: window.runtimeInstallSelectedItem || ({})
    readonly property bool selectedRuntimeInstalled: !!selectedRuntime.installed
    readonly property string footerActionText: selectedRuntimeInstalled ? Strings.t("overwrite") : Strings.t("install")
    readonly property string footerActionBusyText: Strings.t("installing")
    readonly property bool hasSelectedRuntime: !!selectedRuntime && String(selectedRuntime.id || "").length > 0
    property bool installFeedbackVisible: false

    Timer {
        id: installFeedbackHideTimer
        interval: 2000
        repeat: false
        onTriggered: {
            root.installFeedbackVisible = false
            bridge.clearRuntimeInstallFeedback()
        }
    }

    function closeDialog() {
        window.runtimeInstallOpen = false
        bridge.clearRuntimeInstallFeedback()
    }

    function selectRuntime(serverItem) {
        window.runtimeInstallSelectedItem = serverItem || ({})
    }

    function installSelectedRuntime() {
        if (!hasSelectedRuntime || bridge.runtimeInstallBusy) {
            return
        }
        bridge.installServerRuntime(window.runtimeInstallSelectedItem, selectedRuntimeInstalled)
    }

    function syncInstallFeedbackVisibility() {
        if (bridge.runtimeInstallBusy || bridge.runtimeInstallProgress > 0) {
            root.installFeedbackVisible = true
            if (!bridge.runtimeInstallBusy && bridge.runtimeInstallProgress >= 100) {
                installFeedbackHideTimer.restart()
            } else {
                installFeedbackHideTimer.stop()
            }
            return
        }

        if (String(bridge.runtimeInstallStatus || "").length > 0) {
            root.installFeedbackVisible = true
            installFeedbackHideTimer.restart()
            return
        }

        root.installFeedbackVisible = false
        installFeedbackHideTimer.stop()
    }

    onVisibleChanged: {
        if (!visible) {
            window.runtimeInstallSelectedItem = ({})
            root.installFeedbackVisible = false
            installFeedbackHideTimer.stop()
            bridge.clearRuntimeInstallFeedback()
            return
        }

        Qt.callLater(appSettingsWindow.refreshRuntimeServerModel)
        Qt.callLater(root.syncInstallFeedbackVisibility)
    }

    onClosing: function(closeEvent) {
        closeEvent.accepted = true
        window.runtimeInstallOpen = false
        window.runtimeInstallSelectedItem = ({})
        root.installFeedbackVisible = false
        installFeedbackHideTimer.stop()
        bridge.clearRuntimeInstallFeedback()
    }

    Connections {
        target: bridge
        function onAppSettingsFeedbackChanged() {
            root.syncInstallFeedbackVisibility()
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        context: Qt.WindowShortcut
        onActivated: root.closeDialog()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: root.loadedLabel
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                Components.QuickActionButton {
                    id: refreshButton
                    iconSource: "../icons/lucide/rotate-cw.svg"
                    tooltip: Strings.t("refresh")
                    enabled: !bridge.runtimeManagerBusy
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    onClicked: appSettingsWindow.refreshRuntimeServerModel()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surface

                Column {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        width: parent.width
                        height: 30
                        color: Theme.surface

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                Layout.preferredWidth: 230
                                text: Strings.t("runtime")
                                color: Theme.muted
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.preferredWidth: 90
                                text: Strings.t("version")
                                color: Theme.muted
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.preferredWidth: 120
                                text: Strings.t("platform")
                                color: Theme.muted
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Text {
                                Layout.preferredWidth: 80
                                horizontalAlignment: Text.AlignRight
                                text: "Size"
                                color: Theme.muted
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Components.AppScrollArea {
                        width: parent.width
                        height: parent.height - 30
                        viewportMargins: 0
                        clipContent: true

                        Column {
                            width: parent.width
                            spacing: 0

                            Text {
                                visible: appSettingsWindow.runtimeServerModel.length === 0
                                text: bridge.runtimeManagerBusy ? Strings.t("loading.runtimes") : Strings.t("no.server.runtimes.loaded.for.this.service")
                                color: Theme.muted
                                font.pixelSize: 13
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                padding: 30
                            }

                            Repeater {
                                model: appSettingsWindow.runtimeServerModel

                                delegate: Item {
                                    id: runtimeRow
                                    required property int index
                                    property var serverItem: appSettingsWindow.runtimeServerModel[index]
                                    property bool selected: String(window.runtimeInstallSelectedItem.id || "") === String(serverItem.id || "")

                                    width: parent.width
                                    height: 47

                                    Rectangle {
                                        anchors.fill: parent
                                        color: runtimeRow.selected ? Theme.accentStrong : Theme.surface
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectRuntime(serverItem)
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 8
                                        anchors.bottomMargin: 8
                                        spacing: 10

                                        Column {
                                            width: 230
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            Text {
                                                text: String(serverItem.label || serverItem.id || "")
                                                color: runtimeRow.selected ? "white" : Theme.text
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }

                                            Text {
                                                text: String(serverItem.status || "") + " | " + String(serverItem.releaseDateLabel || "-")
                                                color: runtimeRow.selected ? "#f4f4f4" : Theme.muted
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }

                                        Text {
                                            width: 90
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(serverItem.version || "")
                                            color: runtimeRow.selected ? "white" : Theme.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: 120
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(serverItem.platform || "") + " / " + String(serverItem.arch || "")
                                            color: runtimeRow.selected ? "white" : Theme.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }

                                        Item {
                                            width: Math.max(0, parent.width - (230 + 90 + 120 + 80 + 3 * 10))
                                        }

                                        Text {
                                            width: 80
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            text: String(serverItem.sizeLabel || "")
                                            color: runtimeRow.selected ? "white" : Theme.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        visible: runtimeRow.index < appSettingsWindow.runtimeServerModel.length - 1
                                        x: 0
                                        y: parent.height - 1
                                        width: parent.width
                                        height: 1
                                        color: Theme.border
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: String(bridge.runtimeInstallStatus || "")
                    color: bridge.appSettingsError ? "#bb4d4d" : Theme.muted
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                    visible: root.installFeedbackVisible && text.length > 0
                }

                ProgressBar {
                    id: runtimeInstallProgressBar
                    Layout.preferredWidth: 180
                    Layout.alignment: Qt.AlignVCenter
                    from: 0
                    to: 100
                    value: bridge.runtimeInstallProgress
                    visible: root.installFeedbackVisible
                    indeterminate: bridge.runtimeInstallBusy && bridge.runtimeInstallProgress < 5
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: 8

                Components.AppButton {
                    text: Strings.t("cancel")
                    enabled: !bridge.runtimeInstallBusy
                    Layout.alignment: Qt.AlignLeft
                    onClicked: root.closeDialog()
                }

                Item {
                    Layout.fillWidth: true
                }

                Components.AppButton {
                    text: bridge.runtimeInstallBusy ? root.footerActionBusyText : root.footerActionText
                    visible: root.hasSelectedRuntime
                    enabled: root.hasSelectedRuntime && !bridge.runtimeInstallBusy
                    highlighted: true
                    textColor: "white"
                    Layout.alignment: Qt.AlignRight
                    onClicked: root.installSelectedRuntime()
                }
            }
        }
    }
}
