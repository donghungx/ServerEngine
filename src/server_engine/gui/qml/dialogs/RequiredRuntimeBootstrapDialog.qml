import QtQuick
import QtQuick.Controls
import "../components" as Components
import "../theme"
import "../i18n"

Window {
    id: root
    required property var bridge

    visible: bridge.requiredRuntimeBootstrapOpen
    width: 640
    height: 256
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height
    title: Strings.t("preparing.required.runtimes")
    color: Theme.surface
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.CustomizeWindowHint | Qt.WindowTitleHint

    Components.AppWindowFrame {
        title: root.title
        moveWindow: root
        contentMargins: 20
        contentTopMargin: 8
        contentSpacing: 12

        Column {
            anchors.fill: parent
            spacing: 12

            Text {
                text: Strings.t("server.engine.is.installing.required.defaults.before.use")
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                width: parent.width
                font.weight: Font.Medium
            }

            Rectangle {
                width: parent.width
                height: 140
                radius: Theme.radius
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: 1

                Components.AppScrollArea {
                    anchors.fill: parent
                    viewportMargins: 10
                    clipContent: true

                    Column {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: bridge.requiredRuntimeBootstrapItems

                            delegate: Components.StatusProgressRow {
                                required property var modelData
                                width: parent.width
                                label: String(modelData.label || "")
                                status: String(modelData.status || "")
                            }
                        }
                    }
                }
            }

            ProgressBar {
                width: parent.width
                from: 0
                to: 100
                value: bridge.requiredRuntimeBootstrapProgress
                indeterminate: bridge.requiredRuntimeBootstrapBusy
                    && bridge.requiredRuntimeBootstrapProgress < 5
            }

            Text {
                text: String(bridge.requiredRuntimeBootstrapStatus || "")
                color: bridge.requiredRuntimeBootstrapError ? "#bb4d4d" : Theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Row {
                visible: bridge.requiredRuntimeBootstrapError
                spacing: 6

                Components.AppButton {
                    text: bridge.requiredRuntimeBootstrapBusy ? "Working..." : "Retry"
                    enabled: !bridge.requiredRuntimeBootstrapBusy
                    highlighted: true
                    textColor: "white"
                    onClicked: bridge.retryRequiredRuntimeBootstrap()
                }
            }
        }
    }
}
