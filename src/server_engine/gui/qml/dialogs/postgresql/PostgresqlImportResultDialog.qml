import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components" as Components
import "../../theme"
import "../../i18n"

Window {
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

    id: postgresqlImportResultWindow
        visible: root.postgresqlImportPopupOpen
            && (bridge().postgresqlImportBusy
                || bridge().postgresqlImportProgress > 0
                || String(bridge().postgresqlImportMessage || "").length > 0)
        width: 520
        height: 220
        minimumWidth: width
        maximumWidth: width
        minimumHeight: height
        maximumHeight: height
        title: root.postgresqlImportFlowTitleText()
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        Components.AppWindowFrame {
            anchors.fill: parent
            title: root.postgresqlImportFlowTitleText()
            moveWindow: postgresqlImportResultWindow
            contentMargins: 16
            contentSpacing: 12
            footerRightMargin: 16
            footerBottomMargin: 16
            color: Theme.surface

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 12

                Text {
                    text: root.postgresqlImportFlowTitleText()
                    color: Theme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Text {
                    text: root.postgresqlImportDatabaseName
                    color: Theme.muted
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 12
                    radius: 6
                    color: Theme.muted
                    visible: bridge().postgresqlImportBusy || bridge().postgresqlImportProgress > 0

                    Rectangle {
                        width: parent.width * (bridge().postgresqlImportProgress / 100.0)
                        height: parent.height
                        radius: 6
                        color: Theme.accentStrong

                        Behavior on width {
                            NumberAnimation { duration: 120 }
                        }
                    }
                }

                Text {
                    text: bridge().postgresqlImportBusy
                        ? (bridge().postgresqlImportProgressLabel + " " + bridge().postgresqlImportProgress + "%")
                        : String(bridge().postgresqlImportMessage || "")
                    color: bridge().postgresqlImportBusy
                        ? Theme.text
                        : (bridge().postgresqlImportError ? "#bb4d4d" : "#4aa94b")
                    font.pixelSize: 13
                    wrapMode: Text.NoWrap
                    Layout.fillWidth: true
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }

            footerRight: Row {
                spacing: 10

                Components.AppButton {
                    text: Strings.t("dismiss")
                    visible: !bridge().postgresqlImportBusy
                    onClicked: bridge().clearPostgresqlRuntimeFeedback && bridge().clearPostgresqlRuntimeFeedback()
                }
            }
        }
    }
