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

        id: mongodbDropConfirmWindow
        visible: root.mongodbDropConfirmOpen
        width: 520
        height: Math.max(180, dropConfirmContent.implicitHeight + 96)
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("confirm.drop.mongodb.database")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (!visible) {
                root.mongodbDropConfirmOpen = false
                root.mongodbDropDatabaseName = ""
            }
        }

        Components.AppWindowFrame {
            anchors.fill: parent
            title: Strings.t("drop.mongodb.database")
            moveWindow: mongodbDropConfirmWindow
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
                    text: Strings.t("this.will.permanently.delete") + root.mongodbDropDatabaseName + "'. This action cannot be undone."
                    color: "#bb4d4d"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: String(bridge().mongodbRuntimeMessage || "")
                    color: bridge().mongodbRuntimeError ? "#bb4d4d" : "#4aa94b"
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: String(bridge().mongodbRuntimeMessage || "").length > 0
                    Layout.fillWidth: true
                }
            }

            footerRight: Row {
                spacing: 10

                Components.AppButton {
                    text: Strings.t("cancel")
                    enabled: !bridge().mongodbActionBusy
                    onClicked: root.mongodbDropConfirmOpen = false
                }

                Components.AppButton {
                    text: Strings.t("drop")
                    enabled: !bridge().mongodbActionBusy
                        && String(root.mongodbDropDatabaseName || "").length > 0
                    onClicked: {
                        var ok = bridge().dropMongodbDatabase && bridge().dropMongodbDatabase(root.mongodbDropDatabaseName)
                        if (ok) {
                            root.mongodbDropConfirmOpen = false
                        }
                    }
                }
            }
        }
    }
