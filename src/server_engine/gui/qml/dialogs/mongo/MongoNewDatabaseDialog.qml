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

        id: newMongodbDatabaseWindow
        visible: root.newMongodbDatabasePopupOpen
        width: 520
        height: 250
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("new.mongodb.database")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null

        flags: Qt.Dialog
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (visible) {
                mongodbDatabaseNameInput.text = ""
                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
            } else {
                root.newMongodbDatabasePopupOpen = false
                mongodbDatabaseNameInput.text = ""
                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
            }
        }

        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 24
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) {
                newMongodbDatabaseWindow.startSystemMove()
                mouse.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                color: "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 88
                    anchors.verticalCenter: parent.verticalCenter
                    text: Strings.t("create.mongodb.database")
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 16
                spacing: 16

                Label {
                    text: Strings.t("create.a.new.mongodb.database.in.the.active")
                + String(bridge().activeMongodbRuntimeLabel || "MongoDB")
                + " runtime."
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Components.AppTextField {
                    id: mongodbDatabaseNameInput
                    Layout.fillWidth: true
                    placeholderText: Strings.t("database.name")
                }

                Label {
                    visible: text.length > 0

                    text: String(bridge().mongodbRuntimeMessage || "")

                    color: bridge().mongodbRuntimeError
                        ? "#bb4d4d"
                        : "#4aa94b"

                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    Components.AppButton {
                        text: Strings.t("cancel")

                        onClicked: root.newMongodbDatabasePopupOpen = false
                    }

                    Components.AppButton {
                        text: Strings.t("confirm")

                        highlighted: true
                        textColor: "white"

                    onClicked: {
                        if (bridge().createMongodbDatabase && bridge().createMongodbDatabase(
                            mongodbDatabaseNameInput.text,
                            ""
                        )) {
                            mongodbDatabaseNameInput.text = ""
                            root.newMongodbDatabasePopupOpen = false
                            bridge().refreshMongodbRuntime && bridge().refreshMongodbRuntime()
                        }
                    }
                }
            }
        }
        }
    }
