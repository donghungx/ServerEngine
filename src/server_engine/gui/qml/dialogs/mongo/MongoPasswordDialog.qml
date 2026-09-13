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

        id: mongodbPasswordWindow
        visible: root.mongodbPasswordPopupOpen
        width: 540
        height: 250
        minimumWidth: width
        maximumWidth: width

        minimumHeight: height
        maximumHeight: height
        title: Strings.t("root.password")
        color: Theme.surface
        modality: Qt.ApplicationModal
        transientParent: root && root.Window ? root.Window.window : null

        flags: Qt.Dialog
            | Qt.CustomizeWindowHint
            | Qt.WindowTitleHint
            | Qt.WindowCloseButtonHint

        onVisibleChanged: {
            if (visible) {
                mongodbPasswordInput.text = bridge().mongodbPassword
                root.mongodbPasswordFeedback = ""
                root.mongodbPasswordFeedbackError = false
                bridge().clearMongodbRuntimeFeedback && bridge().clearMongodbRuntimeFeedback()
            } else {
                root.mongodbPasswordPopupOpen = false
                mongodbPasswordInput.text = ""
                root.mongodbPasswordFeedback = ""
                root.mongodbPasswordFeedbackError = false
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
                mongodbPasswordWindow.startSystemMove()
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
                    text: Strings.t("root.password")
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
                    text: Strings.t("review.the.current.stored.root.password.and.optionally.change.it.for.the.active")
                    + String(bridge().activeMongodbRuntimeLabel || "MongoDB")
                    + " runtime."
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Components.AppTextField {
                    id: mongodbPasswordInput
                    Layout.fillWidth: true
                    placeholderText: Strings.t("root.password")
                    echoMode: TextInput.Normal
                }

                Label {
                    visible: text.length > 0

                    text: String(root.mongodbPasswordFeedback || "").length > 0
                        ? root.mongodbPasswordFeedback
                        : String(bridge().mongodbRuntimeMessage || "")

                    color: String(root.mongodbPasswordFeedback || "").length > 0
                        ? (root.mongodbPasswordFeedbackError ? "#bb4d4d" : "#4aa94b")
                        : (bridge().mongodbRuntimeError ? "#bb4d4d" : "#4aa94b")

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

                        onClicked: root.mongodbPasswordPopupOpen = false
                    }

                    Components.AppButton {
                        text: Strings.t("settings.appearance.save")
                        highlighted: true
                        textColor: "white"

                        onClicked: {
                            if (mongodbPasswordInput.text.length === 0) {
                                root.mongodbPasswordFeedback = "Password is required."
                                root.mongodbPasswordFeedbackError = true
                            } else if (bridge().updateMongodbPassword && bridge().updateMongodbPassword(mongodbPasswordInput.text)) {
                                root.mongodbPasswordFeedback = ""
                                root.mongodbPasswordFeedbackError = false
                                mongodbPasswordInput.text = ""
                                root.mongodbPasswordPopupOpen = false
                                bridge().refreshMongodbRuntime && bridge().refreshMongodbRuntime()
                            } else {
                                root.mongodbPasswordFeedback = ""
                                root.mongodbPasswordFeedbackError = false
                            }
                        }
                    }
                }
            }
        }
    }
