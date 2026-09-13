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

    id: postgresqlDropConfirmWindow
        visible: root.postgresqlDropConfirmOpen
        width: 520
        height: Math.max(180, dropConfirmContent.implicitHeight + 96)
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("confirm.drop.postgresql.database")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (!visible) {
                root.postgresqlDropConfirmOpen = false
                root.postgresqlDropDatabaseName = ""
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("drop.postgresql.database")
            moveWindow: postgresqlDropConfirmWindow
            contentMargins: 16
            contentSpacing: 12
            footerRightMargin: 0
            footerBottomMargin: 0
            color: Theme.surface

            ColumnLayout {
                id: dropConfirmContent
                anchors.fill: parent
                spacing: 12

                Text {
                    text: Strings.t("drop.database")
                    color: Theme.text
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }

                Text {
                    text: Strings.t("this.will.permanently.delete") + root.postgresqlDropDatabaseName + "'. This action cannot be undone."
                    color: "#bb4d4d"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: String(bridge().postgresqlRuntimeMessage || "")
                    color: bridge().postgresqlRuntimeError ? "#bb4d4d" : "#4aa94b"
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: String(bridge().postgresqlRuntimeMessage || "").length > 0
                    Layout.fillWidth: true
                }
            }

            footerRight: Row {
                spacing: 10

                Components.AppButton {
                    text: Strings.t("cancel")
                    enabled: !bridge().postgresqlActionBusy
                    onClicked: root.postgresqlDropConfirmOpen = false
                }

                Components.AppButton {
                    text: Strings.t("drop")
                    enabled: !bridge().postgresqlActionBusy
                        && String(root.postgresqlDropDatabaseName || "").length > 0
                    onClicked: {
                        var ok = bridge().dropPostgresqlDatabase ? bridge().dropPostgresqlDatabase(root.postgresqlDropDatabaseName) : false
                        if (ok) {
                            root.postgresqlDropConfirmOpen = false
                        }
                    }
                }
            }
        }
    }
